import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSource implements BodyMetricsSource {
  List<BodyMetric> data = [];
  final requestedStarts = <DateTime>[];

  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async {
    requestedStarts.add(start);
    return data.where((m) => !m.date.isBefore(start)).toList();
  }
}

BodyMetric metric(int month, int day, double kg) => BodyMetric(
  date: DateTime(2026, month, day),
  measuredAt: DateTime(2026, month, day, 7, 30),
  weightKg: kg,
  bodyFatPercent: 20,
  leanMassKg: kg * 0.8,
  leanMassEstimated: true,
);

void main() {
  late AppDatabase db;
  late FakeSource source;
  late BodyRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = FakeSource();
    repo = BodyRepository(db, source, clock: () => DateTime(2026, 10, 8, 9));
  });

  tearDown(() => db.close());

  Future<List<BodyMetric>> cached() => repo.watchSince(DateTime(2000)).first;

  test('快取是空的時候抓 90 天，資料完整寫回', () async {
    source.data = [metric(10, 1, 72), metric(10, 7, 71.5)];

    expect(await repo.sync(), 2);

    expect(source.requestedStarts.single, DateTime(2026, 7, 11));
    final rows = await cached();
    expect(rows.map((m) => m.date), [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 7),
    ]);
    final first = rows.first;
    expect(first.measuredAt, DateTime(2026, 10, 1, 7, 30));
    expect(first.weightKg, 72);
    expect(first.bodyFatPercent, 20);
    expect(first.leanMassKg, closeTo(57.6, 1e-9));
    expect(first.leanMassEstimated, isTrue);
  });

  test('之後從快取最後一天往前 14 天重抓', () async {
    source.data = [metric(10, 1, 72)];
    await repo.sync();

    await repo.sync();
    expect(source.requestedStarts.last, DateTime(2026, 9, 17));
  });

  test('重抓範圍內被刪掉的天會從快取移除，範圍外的保留', () async {
    source.data = [metric(9, 1, 74), metric(10, 1, 72), metric(10, 7, 71.5)];
    await repo.sync();

    // 健康 App 裡刪掉 10/1，10/7 數值被修改
    source.data = [metric(9, 1, 74), metric(10, 7, 71.0)];
    await repo.sync();

    final rows = await cached();
    expect(rows.map((m) => (m.date.month, m.date.day, m.weightKg)), [
      (9, 1, 74.0),
      (10, 7, 71.0),
    ]);
  });

  test('讀到空資料時不清掉快取（iOS 被拒絕讀取時只會拿到空資料）', () async {
    source.data = [metric(10, 1, 72)];
    await repo.sync();

    source.data = [];
    expect(await repo.sync(), 0);
    expect(await cached(), hasLength(1));
  });

  test('watchSince 只回傳指定日期之後的資料', () async {
    source.data = [metric(9, 1, 74), metric(10, 1, 72)];
    await repo.sync();

    final rows = await repo.watchSince(DateTime(2026, 9, 2)).first;
    expect(rows.map((m) => m.date), [DateTime(2026, 10, 1)]);
  });
}
