import 'package:body_lab/analysis/combo_heatmap.dart';
import 'package:body_lab/analysis/daily_dataset.dart';
import 'package:body_lab/analysis/phase_summary.dart';
import 'package:body_lab/data/body_repository.dart';
import 'package:body_lab/data/check_repository.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/data/phase_repository.dart';
import 'package:body_lab/data/template_repository.dart';
import 'package:body_lab/dev/demo_data.dart';
import 'package:body_lab/models/body_metric.dart';
import 'package:body_lab/services/health_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSource implements BodyMetricsSource {
  @override
  Future<List<BodyMetric>> fetchDailyMetrics(DateTime start) async => [];
}

void main() {
  final today = DateTime(2026, 10, 8);

  late AppDatabase db;
  late BodyRepository body;
  late FoodRepository food;
  late TemplateRepository templates;
  late CheckRepository checks;
  late PhaseRepository phases;
  late DatasetRepository dataset;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    body = BodyRepository(db, _NoSource(), clock: () => today);
    food = FoodRepository(db);
    templates = TemplateRepository(db);
    checks = CheckRepository(db);
    phases = PhaseRepository(db);
    dataset = DatasetRepository(
      db,
      body,
      food,
      checks,
      phases,
      clock: () => today,
    );

    // 先放一筆舊資料，確認會被清掉
    await phases.save(
      PhasesCompanion.insert(
        name: '舊階段',
        startDay: '2026-01-01',
        endDay: '2026-01-28',
      ),
    );

    await seedDemoData(
      db: db,
      body: body,
      templates: templates,
      checks: checks,
      phases: phases,
      today: today,
    );
  });

  tearDown(() => db.close());

  test('清掉舊資料，產生 12 週資料與 3 個階段', () async {
    final all = await phases.all();
    expect(all.map((p) => p.name), ['減脂', '高蛋白 + 肌酸', '維持期']);

    final ds = await dataset.loadAll();
    expect(ds.days, hasLength(kDemoDays));
    expect(ds.to, today);

    final weighDays = ds.days.where((d) => d.metric != null).length;
    final foodDays = ds.days.where((d) => d.food != null).length;
    expect(weighDays, inInclusiveRange(65, 84));
    expect(foodDays, inInclusiveRange(60, 84));

    // 範本：預設蛋白粉 + 10 個示範範本，有使用次數
    final list = await templates.watchTemplates().first;
    expect(list, hasLength(11));
    expect(list.first.name, '蛋白粉（1 匙）');
    expect(list.first.useCount, greaterThan(0));
  });

  test('階段結果符合設計：維持期脂肪微升、之後兩階段脂肪下降', () async {
    final ds = await dataset.loadAll();
    final byName = {
      for (final p in await phases.all()) p.name: summarizePhase(p, ds, today),
    };

    final maintain = byName['維持期']!;
    final highProtein = byName['高蛋白 + 肌酸']!;
    final cut = byName['減脂']!;

    expect(maintain.status, PhaseStatus.done);
    expect(cut.status, PhaseStatus.active);
    expect(highProtein.range.avgProteinG!, greaterThan(140));
    expect(maintain.range.avgProteinG!, lessThan(100));
    expect(highProtein.creatineDays!, greaterThan(20));

    expect(maintain.range.fatMassChange!, greaterThan(0));
    expect(highProtein.range.fatMassChange!, lessThan(0));
    expect(cut.perWeek(cut.range.fatMassChange)!, lessThan(0));
  });

  test('熱力圖有足夠的週樣本，高蛋白 + 肌酸的格子脂肪下降', () async {
    final samples = weeklySamples(await dataset.loadAll());
    expect(samples, hasLength(12));

    final h = buildHeatmap(
      samples,
      x: HeatmapFactor.protein,
      y: HeatmapFactor.creatine,
      outcome: HeatmapOutcome.fatMass,
    );
    expect(h.used, greaterThanOrEqualTo(8));
    final noCreatine = h.cells.entries.where((e) => e.key.$2 == 0);
    final withCreatine = h.cells.entries.where((e) => e.key.$2 == 1);
    expect(noCreatine.every((e) => e.value.mean > 0), isTrue);
    expect(withCreatine.every((e) => e.value.mean < 0), isTrue);
  });
}
