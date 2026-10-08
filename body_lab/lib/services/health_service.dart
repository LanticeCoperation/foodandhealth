import 'dart:io';

import 'package:health/health.dart';

import '../models/body_metric.dart';
import '../utils/dates.dart';

enum BodySampleType { weight, bodyFat, leanMass }

/// 與平台無關的單筆量測；體脂一律是 0–100。
class BodySample {
  const BodySample(this.type, this.time, this.value);

  final BodySampleType type;
  final DateTime time;
  final double value;
}

/// 每種數值各取當天最早一筆，組成每日資料。沒有體重的日子略過。
/// 除脂體重缺值但有體脂時，以 體重 × (1 − 體脂%) 推算。
/// 回傳依日期由舊到新排序。
List<BodyMetric> buildDailyMetrics(Iterable<BodySample> samples) {
  final firstOfDay = <DateTime, Map<BodySampleType, BodySample>>{};

  for (final s in samples) {
    final day = dateOnly(s.time);
    final byType = firstOfDay.putIfAbsent(day, () => {});
    final existing = byType[s.type];
    if (existing == null || s.time.isBefore(existing.time)) {
      byType[s.type] = s;
    }
  }

  final days = firstOfDay.keys.toList()..sort();
  final result = <BodyMetric>[];
  for (final day in days) {
    final byType = firstOfDay[day]!;
    final weight = byType[BodySampleType.weight];
    if (weight == null) continue;

    final bodyFat = byType[BodySampleType.bodyFat]?.value;
    var lean = byType[BodySampleType.leanMass]?.value;
    var estimated = false;
    if (lean == null && bodyFat != null) {
      lean = weight.value * (1 - bodyFat / 100);
      estimated = true;
    }

    result.add(
      BodyMetric(
        date: day,
        measuredAt: weight.time.toLocal(),
        weightKg: weight.value,
        bodyFatPercent: bodyFat,
        leanMassKg: lean,
        leanMassEstimated: estimated,
      ),
    );
  }
  return result;
}

enum HealthAccess {
  granted,

  /// Android：沒安裝 Health Connect（Android 13 以下）。
  healthConnectMissing,

  /// Android：Health Connect 需要更新。
  healthConnectUpdateRequired,

  denied,
}

/// 每日身體組成的來源；同步邏輯只依賴這個介面，方便測試。
abstract interface class BodyMetricsSource {
  /// 讀取 [start]（當地日期 00:00）到現在的每日身體組成，依日期由舊到新。
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start);
}

class HealthService implements BodyMetricsSource {
  final Health _health = Health();
  bool _configured = false;

  static const _types = [
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.LEAN_BODY_MASS,
  ];
  static final _readOnly = List.filled(_types.length, HealthDataAccess.READ);

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// 檢查 Health Connect 狀態並要求讀取權限。
  ///
  /// iOS 的 HealthKit 不會透露使用者是否拒絕讀取，被拒時只會讀到空資料，
  /// 所以 iOS 這裡幾乎都回傳 [HealthAccess.granted]。
  Future<HealthAccess> ensureAccess() async {
    await _configure();

    if (Platform.isAndroid) {
      final status = await _health.getHealthConnectSdkStatus();
      if (status == HealthConnectSdkStatus.sdkUnavailable) {
        return HealthAccess.healthConnectMissing;
      }
      if (status ==
          HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
        return HealthAccess.healthConnectUpdateRequired;
      }
    }

    final has = await _health.hasPermissions(_types, permissions: _readOnly);
    if (has != true) {
      final ok = await _health.requestAuthorization(
        _types,
        permissions: _readOnly,
      );
      if (!ok) return HealthAccess.denied;
    }

    // Health Connect 預設只能讀授權後 30 天內的資料，另外要求歷史資料權限。
    // 被拒也沒關係，只是讀到的天數比較少。
    if (Platform.isAndroid &&
        await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }

    return HealthAccess.granted;
  }

  Future<void> installHealthConnect() => _health.installHealthConnect();

  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async {
    await _configure();
    final now = DateTime.now();

    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: start,
      endTime: now,
    );

    return buildDailyMetrics(
      _health.removeDuplicates(points).map(_toSample).whereType<BodySample>(),
    );
  }

  BodySample? _toSample(HealthDataPoint p) {
    final value = p.value;
    if (value is! NumericHealthValue) return null;
    final v = value.numericValue.toDouble();

    switch (p.type) {
      case HealthDataType.WEIGHT:
        return BodySample(BodySampleType.weight, p.dateFrom, v);
      case HealthDataType.LEAN_BODY_MASS:
        return BodySample(BodySampleType.leanMass, p.dateFrom, v);
      case HealthDataType.BODY_FAT_PERCENTAGE:
        // HealthKit 的 percent 單位是 0–1，Health Connect 是 0–100。
        return BodySample(
          BodySampleType.bodyFat,
          p.dateFrom,
          Platform.isIOS ? v * 100 : v,
        );
      default:
        return null;
    }
  }
}
