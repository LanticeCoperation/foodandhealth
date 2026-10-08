import 'package:body_lab/analysis/combo_heatmap.dart';
import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/analysis/energy.dart';
import 'package:body_lab/analysis/overlay_chart.dart';
import 'package:body_lab/data/activity_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:body_lab/utils/dates.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeActivity implements ActivitySource {
  Map<DateTime, double> data = {};
  final requestedStarts = <DateTime>[];

  @override
  Future<Map<DateTime, double>> fetchDailyActiveEnergy(DateTime start) async {
    requestedStarts.add(start);
    return {
      for (final e in data.entries)
        if (!e.key.isBefore(start)) e.key: e.value,
    };
  }
}

DayTotals food(double kcal) =>
    DayTotals(kcal: kcal, proteinG: 0, carbsG: 0, fatG: 0, missingKcal: 0);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<EnergyModel> model(EnergyMode mode) async {
    final profile = ProfileRepository(db, clock: () => DateTime(2026, 10, 8));
    // 男 30 歲 180 cm 80 kg：BMR 1780
    await profile.save(
      sex: Sex.male,
      birthYear: 1996,
      heightCm: 180,
      activity: ActivityLevel.moderate,
      weightKg: 80,
      tdeeKcal: 2760,
      energyMode: mode,
    );
    return EnergyModel((await profile.get())!);
  }

  group('ActivityRepository', () {
    late FakeActivity source;
    late ActivityRepository repo;

    setUp(() {
      source = FakeActivity();
      repo = ActivityRepository(
        db,
        source,
        clock: () => DateTime(2026, 10, 8, 21),
      );
    });

    test('首次抓 90 天，之後從最後一天往前 3 天重抓並取代', () async {
      source.data = {
        DateTime(2026, 10, 1): 400,
        DateTime(2026, 10, 7): 500,
        DateTime(2026, 10, 8): 200,
      };
      expect(await repo.sync(), 3);
      expect(source.requestedStarts.last, DateTime(2026, 7, 11));

      // 今天的消耗增加、10/7 被刪掉
      source.data = {DateTime(2026, 10, 1): 400, DateTime(2026, 10, 8): 650};
      await repo.sync();
      expect(source.requestedStarts.last, DateTime(2026, 10, 5));
      expect(await repo.since(DateTime(2026, 1, 1)), {
        DateTime(2026, 10, 1): 400.0,
        DateTime(2026, 10, 8): 650.0,
      });
      expect(await repo.watchDay(DateTime(2026, 10, 8)).first, 650);
      expect(await repo.watchDay(DateTime(2026, 10, 7)).first, isNull);
    });

    test('讀到空資料時不清掉快取', () async {
      source.data = {DateTime(2026, 10, 8): 300};
      await repo.sync();
      source.data = {};
      await repo.sync();
      expect(await repo.watchDay(DateTime(2026, 10, 8)).first, 300);
    });
  });

  group('EnergyModel', () {
    test('手錶模式：基礎代謝 + 活動消耗；沒有手錶資料用 TDEE', () async {
      final e = await model(EnergyMode.watch);
      expect(e.bmr, 1780);
      expect(e.expenditure(450), 2230);
      expect(e.fromWatch(450), isTrue);
      expect(e.expenditure(null), 2760);
      expect(e.fromWatch(null), isFalse);
    });

    test('固定模式：一律 TDEE', () async {
      final e = await model(EnergyMode.fixed);
      expect(e.expenditure(450), 2760);
      expect(e.fromWatch(450), isFalse);
    });

    test('新存的個人資料預設手錶模式', () async {
      final profile = ProfileRepository(db);
      await profile.save(
        sex: Sex.female,
        birthYear: 1990,
        heightCm: 160,
        activity: ActivityLevel.light,
        weightKg: 55,
        tdeeKcal: 1800,
      );
      expect((await profile.get())!.energyMode, EnergyMode.watch);
    });
  });

  group('用每日消耗分析', () {
    // 10/1～10/14：每天吃 2000；第一週活動 300（消耗 2080），第二週活動 900（消耗 2680）
    final from = DateTime(2026, 10, 1);
    final ds = buildDataset(
      from: from,
      to: DateTime(2026, 10, 14),
      metrics: const [],
      food: {for (var i = 0; i < 14; i++) addDays(from, i): food(2000)},
      checks: const {},
      activity: {
        for (var i = 0; i < 14; i++) addDays(from, i): i < 7 ? 300 : 900,
      },
    );

    test('每週平均熱量差與依赤字分組', () async {
      final e = await model(EnergyMode.watch);
      final samples = weeklySamples(
        ds,
        expenditureOf: (d) => e.expenditure(d.activeKcal),
      );
      expect(samples.map((s) => s.balance), [-80, -680]);

      final b = bucketsFor(HeatmapFactor.kcal, samples);
      expect(b.labels, ['赤字 >500', '赤字 0–500', '盈餘']);
      expect(samples.map(b.classify), [1, 0]);
    });

    test('沒有個人資料時熱量退回三分位分組', () {
      final samples = weeklySamples(ds);
      expect(samples.every((s) => s.balance == null), isTrue);
      expect(bucketsFor(HeatmapFactor.kcal, samples).labels, ['全部']);
    });

    test('區間摘要的平均熱量差、疊加圖的每日消耗折線', () async {
      final e = await model(EnergyMode.watch);
      double? exp(DayRecord d) => e.expenditure(d.activeKcal);

      final s = summarize(ds.days, expenditureOf: exp);
      expect(s.avgBalance, closeTo((-80 * 7 - 680 * 7) / 14, 1e-9));
      expect(summarize(ds.days).avgBalance, isNull);

      final o = buildOverlay(
        ds,
        series: {BodySeries.weight},
        intake: IntakeSeries.kcal,
        expenditureOf: exp,
      );
      expect(o.expenditure.map((p) => p.y).toSet(), {2080, 2680});
      // 右軸範圍要放得下消耗（2680 × 1.1 → 3000）
      expect(o.intakeMax, 3000);

      final protein = buildOverlay(
        ds,
        series: {BodySeries.weight},
        intake: IntakeSeries.protein,
        expenditureOf: exp,
      );
      expect(protein.expenditure, isEmpty);
    });
  });
}
