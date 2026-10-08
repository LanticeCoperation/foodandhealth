import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/phase_repository.dart';
import '../utils/dates.dart';
import 'daily_dataset.dart';
import 'overlay_chart.dart';

/// 熱量在目標 ±10% 內算達標。
const double kKcalTolerance = 0.10;

enum PhaseStatus {
  upcoming('尚未開始'),
  active('進行中'),
  done('已結束');

  const PhaseStatus(this.label);
  final String label;
}

class PhaseSummary {
  const PhaseSummary({
    required this.phase,
    required this.status,
    required this.elapsedDays,
    required this.range,
    this.kcalHitDays,
    this.proteinHitDays,
    this.creatineDays,
  });

  final Phase phase;
  final PhaseStatus status;

  /// 已經過的天數（含今天，不超過階段長度）。
  final int elapsedDays;

  /// 階段開始到今天（或結束日）的摘要。
  final RangeSummary range;

  /// 有設目標才有值：達標的天數（只算有飲食紀錄的天）。
  final int? kcalHitDays;
  final int? proteinHitDays;

  /// 階段設定要吃肌酸才有值。
  final int? creatineDays;

  double get progress => elapsedDays / phase.lengthDays;

  /// 換算成每 7 天的變化，長度不同的階段才能比較。
  double? perWeek(double? change) {
    if (change == null || elapsedDays < 2) return null;
    return change / (elapsedDays - 1) * 7;
  }
}

PhaseSummary summarizePhase(
  Phase p,
  DailyDataset ds,
  DateTime today, {
  double? Function(DayRecord)? expenditureOf,
}) {
  final t = dateOnly(today);
  final status = t.isBefore(p.start)
      ? PhaseStatus.upcoming
      : (t.isAfter(p.end) ? PhaseStatus.done : PhaseStatus.active);
  final last = t.isBefore(p.end) ? t : p.end;
  final days = ds.days
      .where((d) => !d.date.isBefore(p.start) && !d.date.isAfter(last))
      .toList();
  final elapsed = status == PhaseStatus.upcoming
      ? 0
      : last.difference(p.start).inDays + 1;

  int? countHits(double? target, bool Function(DayTotals, double) hit) {
    if (target == null) return null;
    return days.where((d) => d.food != null && hit(d.food!, target)).length;
  }

  return PhaseSummary(
    phase: p,
    status: status,
    elapsedDays: elapsed,
    range: summarize(days, expenditureOf: expenditureOf),
    kcalHitDays: countHits(
      p.targetKcal,
      (f, target) => (f.kcal - target).abs() <= target * kKcalTolerance,
    ),
    proteinHitDays: countHits(
      p.targetProteinG,
      (f, target) => f.proteinG >= target,
    ),
    creatineDays: p.creatine
        ? days.where((d) => d.checks.contains(CheckItem.creatine)).length
        : null,
  );
}

/// 新階段的預設起始日：今天，或最後一個階段結束的隔天（取較晚者）。
DateTime suggestPhaseStart(List<Phase> phases, DateTime today) {
  final t = dateOnly(today);
  final ends = phases.map((p) => p.end).toList()..sort();
  if (ends.isEmpty || ends.last.isBefore(t)) return t;
  return addDays(ends.last, 1);
}
