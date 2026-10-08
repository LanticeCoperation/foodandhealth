import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/analysis/phase_summary.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

PhasesCompanion phase(
  String name,
  String start,
  String end, {
  double? kcal,
  double? protein,
  bool creatine = false,
}) => PhasesCompanion.insert(
  name: name,
  startDay: start,
  endDay: end,
  targetKcal: Value(kcal),
  targetProteinG: Value(protein),
  creatine: Value(creatine),
);

void main() {
  group('PhaseRepository', () {
    late AppDatabase db;
    late PhaseRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = PhaseRepository(db);
    });
    tearDown(() => db.close());

    test('新增、依開始日新到舊排序、查某天所在階段', () async {
      await repo.save(phase('A', '2026-09-01', '2026-09-28'));
      await repo.save(phase('B', '2026-10-01', '2026-10-28'));

      final all = await repo.all();
      expect(all.map((p) => p.name), ['B', 'A']);
      expect(all.first.lengthDays, 28);

      expect((await repo.watchOn(DateTime(2026, 9, 28)).first)?.name, 'A');
      expect(await repo.watchOn(DateTime(2026, 9, 29)).first, isNull);
      expect((await repo.watchOn(DateTime(2026, 10, 1, 23)).first)?.name, 'B');
    });

    test('日期重疊時拒絕；修改自己不算重疊', () async {
      final id = await repo.save(phase('A', '2026-09-01', '2026-09-28'));
      expect(
        () => repo.save(phase('B', '2026-09-28', '2026-10-25')),
        throwsA(isA<PhaseOverlapException>()),
      );

      await repo.save(phase('A2', '2026-09-02', '2026-09-29'), id: id);
      expect((await repo.all()).single.name, 'A2');

      await repo.delete(id);
      expect(await repo.all(), isEmpty);
    });
  });

  group('summarizePhase', () {
    final p = Phase(
      id: 1,
      name: '高蛋白 + 肌酸',
      startDay: '2026-10-01',
      endDay: '2026-10-28',
      targetKcal: 2000,
      targetProteinG: 150,
      creatine: true,
      createdAt: DateTime(2026, 9, 30),
    );

    DayTotals food(double kcal, double protein) => DayTotals(
      kcal: kcal,
      proteinG: protein,
      carbsG: 0,
      fatG: 0,
      missingKcal: 0,
    );

    // 9/25～10/31：每天量體重，每天減 0.1 kg
    final ds = buildDataset(
      from: DateTime(2026, 9, 25),
      to: DateTime(2026, 10, 31),
      metrics: [
        for (
          var d = DateTime(2026, 9, 19);
          !d.isAfter(DateTime(2026, 10, 31));
          d = DateTime(d.year, d.month, d.day + 1)
        )
          BodyMetric(
            date: d,
            measuredAt: d,
            weightKg: 80 - d.difference(DateTime(2026, 9, 19)).inDays * 0.1,
          ),
      ],
      food: {
        DateTime(2026, 10, 1): food(2100, 160), // 兩者都達標
        DateTime(2026, 10, 2): food(2300, 150), // 熱量超過 10%
        DateTime(2026, 10, 3): food(1950, 120), // 蛋白質不足
      },
      checks: {
        DateTime(2026, 10, 1): {CheckItem.creatine},
        DateTime(2026, 10, 2): {CheckItem.creatine},
        DateTime(2026, 9, 30): {CheckItem.creatine}, // 階段外不算
      },
      phases: [p],
    );

    test('進行中：只算到今天，執行率與每週變化', () {
      final s = summarizePhase(p, ds, DateTime(2026, 10, 7, 21));
      expect(s.status, PhaseStatus.active);
      expect(s.elapsedDays, 7);
      expect(s.progress, closeTo(7 / 28, 1e-9));
      expect(s.range.totalDays, 7);
      expect(s.kcalHitDays, 2);
      expect(s.proteinHitDays, 2);
      expect(s.creatineDays, 2);
      // 7 日平均每天降 0.1，6 天降 0.6 → 每週 -0.7
      expect(s.range.weightChange, closeTo(-0.6, 1e-9));
      expect(s.perWeek(s.range.weightChange), closeTo(-0.7, 1e-9));
    });

    test('已結束與尚未開始', () {
      final done = summarizePhase(p, ds, DateTime(2026, 10, 31));
      expect(done.status, PhaseStatus.done);
      expect(done.elapsedDays, 28);

      final upcoming = summarizePhase(p, ds, DateTime(2026, 9, 30));
      expect(upcoming.status, PhaseStatus.upcoming);
      expect(upcoming.elapsedDays, 0);
      expect(upcoming.perWeek(-1), isNull);
    });

    test('dataset 每天標上所屬階段', () {
      expect(ds.days.first.phase, isNull);
      expect(
        ds.days.firstWhere((d) => d.date == DateTime(2026, 10, 1)).phase?.id,
        1,
      );
    });

    test('建議起始日：今天或最後階段結束隔天', () {
      expect(
        suggestPhaseStart([], DateTime(2026, 10, 8, 9)),
        DateTime(2026, 10, 8),
      );
      expect(
        suggestPhaseStart([p], DateTime(2026, 10, 8)),
        DateTime(2026, 10, 29),
      );
      expect(
        suggestPhaseStart([p], DateTime(2026, 11, 5)),
        DateTime(2026, 11, 5),
      );
    });
  });
}
