import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/utils/dates.dart';

/// 取代 Apple 健康 / Health Connect 的記憶體版本。
/// 系統的健康授權視窗不是 Flutter 畫面，測試點不到，所以整合測試改用這個。
class FakeHealthService implements HealthService {
  FakeHealthService({
    List<BodySample> samples = const [],
    Map<DateTime, double> activeEnergy = const {},
  }) : samples = [...samples],
       activeEnergy = {...activeEnergy};

  /// 「健康 App」裡現有的量測；手動記錄寫入、刪除都會改這裡。
  final List<BodySample> samples;
  final Map<DateTime, double> activeEnergy;

  @override
  Future<HealthAccess> ensureAccess() async => HealthAccess.granted;

  @override
  Future<void> installHealthConnect() async {}

  @override
  Future<bool> writeBodyMetric({
    required DateTime time,
    required double weightKg,
    double? bodyFatPercent,
  }) async {
    samples.add(
      BodySample(BodySampleType.weight, time, weightKg, fromThisApp: true),
    );
    if (bodyFatPercent != null) {
      samples.add(BodySample(BodySampleType.bodyFat, time, bodyFatPercent));
    }
    return true;
  }

  @override
  Future<bool> deleteBodyMetric(DateTime time) async {
    // 和真的一樣：只刪得到 Body Lab 自己在那個時間寫入的體重與體脂率
    final mine = samples
        .where((s) => s.fromThisApp && _sameMoment(s.time, time))
        .toList();
    if (mine.isEmpty) return false;
    samples.removeWhere(
      (s) =>
          _sameMoment(s.time, time) &&
          (s.fromThisApp || s.type == BodySampleType.bodyFat),
    );
    return true;
  }

  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async =>
      buildDailyMetrics(samples.where((s) => !s.time.isBefore(start)));

  @override
  Future<Map<DateTime, double>> fetchDailyActiveEnergy(DateTime start) async =>
      {
        for (final e in activeEnergy.entries)
          if (!dateOnly(e.key).isBefore(start)) dateOnly(e.key): e.value,
      };

  static bool _sameMoment(DateTime a, DateTime b) =>
      a.difference(b).inSeconds.abs() <= 1;
}
