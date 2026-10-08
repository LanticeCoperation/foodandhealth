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

/// 每日活動消耗的來源（Apple Watch 等寫入的活動能量）。
abstract interface class ActivitySource {
  /// [start]（當地日期 00:00）到現在，每天的活動消耗 kcal。
  /// 已依來源去重（iPhone 與手錶同時記錄不會重複加總）；沒有資料的天不會出現。
  Future<Map<DateTime, double>> fetchDailyActiveEnergy(DateTime start);
}

class HealthService implements BodyMetricsSource, ActivitySource {
  final Health _health = Health();
  bool _configured = false;

  static const _bodyTypes = [
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.LEAN_BODY_MASS,
  ];

  /// 要求讀取權限的所有類型。
  static const _types = [..._bodyTypes, HealthDataType.ACTIVE_ENERGY_BURNED];
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

  /// 手動輸入的體重 / 體脂率寫進 Apple 健康 / Health Connect（標記為手動輸入），
  /// 之後照一般同步讀回來，資料只有健康 App 一份正本。
  /// 第一次會跳出寫入權限；被拒或寫入失敗回傳 false。
  Future<bool> writeBodyMetric({
    required DateTime time,
    required double weightKg,
    double? bodyFatPercent,
  }) async {
    await _configure();
    const types = [HealthDataType.WEIGHT, HealthDataType.BODY_FAT_PERCENTAGE];
    final granted = await _health.requestAuthorization(
      types,
      permissions: const [
        HealthDataAccess.READ_WRITE,
        HealthDataAccess.READ_WRITE,
      ],
    );
    if (!granted) return false;

    var ok = await _health.writeHealthData(
      value: weightKg,
      unit: HealthDataUnit.KILOGRAM,
      type: HealthDataType.WEIGHT,
      startTime: time,
      endTime: time,
      recordingMethod: RecordingMethod.manual,
    );
    if (bodyFatPercent != null) {
      ok &= await _health.writeHealthData(
        // HealthKit 的 percent 單位是 0–1，Health Connect 是 0–100
        value: Platform.isIOS ? bodyFatPercent / 100 : bodyFatPercent,
        unit: HealthDataUnit.PERCENT,
        type: HealthDataType.BODY_FAT_PERCENTAGE,
        startTime: time,
        endTime: time,
        recordingMethod: RecordingMethod.manual,
      );
    }
    return ok;
  }

  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async {
    await _configure();
    final now = DateTime.now();

    final points = await _health.getHealthDataFromTypes(
      types: _bodyTypes,
      startTime: start,
      endTime: now,
    );

    return buildDailyMetrics(
      _health.removeDuplicates(points).map(_toSample).whereType<BodySample>(),
    );
  }

  @override
  Future<Map<DateTime, double>> fetchDailyActiveEnergy(DateTime start) async {
    await _configure();
    // 區間查詢在 iOS 用 HKStatisticsCollectionQuery、在 Android 用 Health Connect
    // 的聚合查詢，兩者都會依來源優先順序去重；直接加總原始紀錄會重複計算。
    final points = await _health.getHealthIntervalDataFromTypes(
      startDate: start,
      endDate: DateTime.now(),
      types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
      interval: const Duration(days: 1).inSeconds,
    );
    final result = <DateTime, double>{};
    for (final p in points) {
      final value = p.value;
      if (value is! NumericHealthValue) continue;
      final kcal = value.numericValue.toDouble();
      if (kcal <= 0) continue; // 沒戴手錶的天當作沒有資料
      final day = dateOnly(p.dateFrom);
      result[day] = (result[day] ?? 0) + kcal;
    }
    return result;
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
