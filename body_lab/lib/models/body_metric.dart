/// 單日身體組成：每種數值都取當天最早一筆（起床測量）。
class BodyMetric {
  const BodyMetric({
    required this.date,
    required this.measuredAt,
    required this.weightKg,
    this.bodyFatPercent,
    this.leanMassKg,
    this.leanMassEstimated = false,
  });

  /// 當地日期，時間固定為 00:00。
  final DateTime date;

  /// 當天第一筆體重的量測時間。
  final DateTime measuredAt;

  final double weightKg;

  /// 0–100。
  final double? bodyFatPercent;

  final double? leanMassKg;

  /// 體脂計沒寫入除脂體重，由 體重 × (1 − 體脂%) 推算。
  final bool leanMassEstimated;

  /// 脂肪重量：優先用體脂%，沒有的話用 體重 − 除脂體重。
  double? get fatMassKg {
    final bf = bodyFatPercent;
    if (bf != null) return weightKg * bf / 100;
    final lean = leanMassKg;
    if (lean != null) return weightKg - lean;
    return null;
  }

  @override
  String toString() =>
      'BodyMetric($date, ${weightKg}kg, bf=$bodyFatPercent%, lean=$leanMassKg'
      '${leanMassEstimated ? '*' : ''})';
}
