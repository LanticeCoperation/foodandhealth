import '../models/body_metric.dart';

/// 移動平均的天數（含當天）。
const int kMovingAverageDays = 7;

/// 體重偏離 7 日平均超過這個值就視為水分波動。
const double kWaterOutlierKg = 0.8;

/// 視窗內至少要有幾天資料，才判斷異常值（避免資料太少時誤判）。
const int kMinPointsForOutlier = 3;

class TrendPoint {
  const TrendPoint({
    required this.metric,
    required this.windowCount,
    required this.weightAvg,
    this.fatMassAvg,
    this.leanMassAvg,
  });

  final BodyMetric metric;

  /// 7 日視窗內實際有資料的天數。
  final int windowCount;

  final double weightAvg;
  final double? fatMassAvg;
  final double? leanMassAvg;

  double get weightDeviation => metric.weightKg - weightAvg;

  bool get isWaterOutlier =>
      windowCount >= kMinPointsForOutlier &&
      weightDeviation.abs() > kWaterOutlierKg;
}

/// 以日曆天計算往前 [windowDays] 天（含當天）的移動平均，缺資料的天直接略過。
/// 回傳依日期由舊到新排序。
List<TrendPoint> computeTrend(
  Iterable<BodyMetric> metrics, {
  int windowDays = kMovingAverageDays,
}) {
  final sorted = metrics.toList()..sort((a, b) => a.date.compareTo(b.date));
  final result = <TrendPoint>[];
  var start = 0;

  for (var i = 0; i < sorted.length; i++) {
    final day = sorted[i].date;
    final windowStart = DateTime(
      day.year,
      day.month,
      day.day - (windowDays - 1),
    );
    while (sorted[start].date.isBefore(windowStart)) {
      start++;
    }
    final window = sorted.sublist(start, i + 1);

    result.add(
      TrendPoint(
        metric: sorted[i],
        windowCount: window.length,
        weightAvg: _average(window.map((m) => m.weightKg))!,
        fatMassAvg: _average(window.map((m) => m.fatMassKg)),
        leanMassAvg: _average(window.map((m) => m.leanMassKg)),
      ),
    );
  }
  return result;
}

double? _average(Iterable<double?> values) {
  final present = values.whereType<double>().toList();
  if (present.isEmpty) return null;
  return present.reduce((a, b) => a + b) / present.length;
}
