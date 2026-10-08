import 'package:flutter/material.dart';

import '../analysis/combo_heatmap.dart';
import '../analysis/daily_dataset.dart';
import '../data/database.dart';
import '../data/profile_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/nutrition_fields.dart';

/// 組合分析熱力圖：兩個因子交叉，看每週身體組成變化的平均。
class ComboScreen extends StatefulWidget {
  const ComboScreen({super.key, required this.dataset, required this.profile});

  final DatasetRepository dataset;
  final ProfileRepository profile;

  @override
  State<ComboScreen> createState() => _ComboScreenState();
}

class _ComboScreenState extends State<ComboScreen> {
  late final Stream<DailyDataset> _all;
  late final Stream<Profile?> _profile;
  HeatmapFactor _x = HeatmapFactor.protein;
  HeatmapFactor _y = HeatmapFactor.creatine;
  HeatmapOutcome _outcome = HeatmapOutcome.fatMass;

  @override
  void initState() {
    super.initState();
    _all = widget.dataset.watchAll();
    _profile = widget.profile.watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Profile?>(
      stream: _profile,
      builder: (context, profileSnap) => StreamBuilder<DailyDataset>(
        stream: _all,
        builder: (context, snapshot) {
          final ds = snapshot.data;
          if (ds == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final tdee = profileSnap.data?.tdeeKcal;
          return _buildBody(ds, tdee);
        },
      ),
    );
  }

  Widget _buildBody(DailyDataset ds, double? tdee) {
    final samples = weeklySamples(ds);
    final heatmap = buildHeatmap(
      samples,
      x: _x,
      y: _y,
      outcome: _outcome,
      tdee: tdee,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _buildControls(),
        const SizedBox(height: 16),
        if (heatmap.used == 0)
          _EmptyHeatmap(total: samples.length)
        else ...[
          _HeatmapGrid(heatmap: heatmap, xTitle: _x.label, yTitle: _y.label),
          const SizedBox(height: 8),
          _ColorLegend(outcome: _outcome),
        ],
        const SizedBox(height: 12),
        _Notes(heatmap: heatmap, tdee: tdee),
        const SizedBox(height: 8),
        _WeekList(samples: samples),
      ],
    );
  }

  Widget _buildControls() {
    DropdownButtonFormField<T> dropdown<T>(
      String label,
      T value,
      List<T> values,
      String Function(T) text,
      ValueChanged<T> onChanged,
    ) => DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(text(v))),
      ],
      onChanged: (v) => onChanged(v as T),
    );

    final factors = HeatmapFactor.values
        .where((f) => f != HeatmapFactor.none)
        .toList();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: dropdown(
                '橫軸',
                _x,
                factors,
                (f) => f.label,
                (v) => setState(() {
                  _x = v;
                  if (_y == v) _y = HeatmapFactor.none;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: dropdown(
                '縱軸',
                _y,
                HeatmapFactor.values.where((f) => f != _x).toList(),
                (f) => f.label,
                (v) => setState(() => _y = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<HeatmapOutcome>(
          segments: [
            for (final o in HeatmapOutcome.values)
              ButtonSegment(value: o, label: Text(o.label)),
          ],
          selected: {_outcome},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _outcome = s.single),
        ),
      ],
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({
    required this.heatmap,
    required this.xTitle,
    required this.yTitle,
  });

  final Heatmap heatmap;
  final String xTitle;
  final String yTitle;

  static const double _cellWidth = 64;
  static const double _labelWidth = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = heatmap;
    final small = theme.textTheme.bodySmall;

    Widget cell(int x, int y) {
      final c = h.cells[(x, y)];
      if (c == null) {
        return Container(
          height: 56,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text('—', style: small),
        );
      }
      final faded = c.n < kMinSamplesPerCell;
      final mean = c.mean;
      return Container(
        height: 56,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: context.palette.heat(h.score(c), faded: faded),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${mean > 0 ? '+' : ''}${mean.toStringAsFixed(2)}',
              style: theme.textTheme.titleSmall,
            ),
            Text(faded ? 'n=${c.n} 少' : 'n=${c.n}', style: small),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${h.outcome.label}每週變化（kg）　縱軸：$yTitle　橫軸：$xTitle',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(_cellWidth),
            columnWidths: const {0: FixedColumnWidth(_labelWidth)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final label in h.xLabels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: small,
                      ),
                    ),
                ],
              ),
              for (final (y, label) in h.yLabels.indexed)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        label,
                        style: small,
                        textAlign: TextAlign.right,
                      ),
                    ),
                    for (var x = 0; x < h.xLabels.length; x++) cell(x, y),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorLegend extends StatelessWidget {
  const _ColorLegend({required this.outcome});

  final HeatmapOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final goodText = outcome.higherIsBetter ? '增加' : '減少';
    return Row(
      children: [
        Text('較差', style: small),
        const SizedBox(width: 6),
        for (final s in [-1.0, -0.5, 0.0, 0.5, 1.0])
          Container(width: 24, height: 12, color: context.palette.heat(s)),
        const SizedBox(width: 6),
        Text('較好（$goodText）', style: small),
      ],
    );
  }
}

class _EmptyHeatmap extends StatelessWidget {
  const _EmptyHeatmap({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          total == 0
              ? '還沒有完整的一週資料。'
              : '$total 週裡還沒有可用的樣本。\n'
                    '每週需要至少 $kMinFoodDaysPerWeek 天飲食紀錄（用到熱量 / 蛋白質時），'
                    '而且這週和上週的 7 日平均都要有至少 $kMinWeighInsForAverage 次量測。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.heatmap, this.tdee});

  final Heatmap heatmap;
  final double? tdee;

  @override
  Widget build(BuildContext context) {
    return Text(
      '每格是落在該組合的週，${heatmap.outcome.label} 7 日平均每週變化的平均。'
      '共 ${heatmap.total} 週，可用 ${heatmap.used} 週。'
      '${tdee == null ? '熱量依自己資料的三分位分成低 / 中 / 高（在身體頁右上角設定 TDEE 後改為依赤字分組）' : '熱量依平均每日赤字（相對固定 TDEE ${tdee!.round()} kcal）分組'}；肌酸一週 $kCreatineDaysPerWeek 天以上算有；'
      '階段以一週有 4 天以上在該階段為準。\n'
      '這是相關不是因果：同一組合的週可能還有其他差異（睡眠、訓練量），樣本少時參考就好。',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList({required this.samples});

  final List<WeekSample> samples;

  @override
  Widget build(BuildContext context) {
    String kg(double? v) =>
        v == null ? '—' : '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';

    return Card(
      child: ExpansionTile(
        title: Text('各週資料（${samples.length} 週）'),
        children: [
          for (final s in samples.reversed)
            ListTile(
              dense: true,
              title: Text(
                '${s.start.month}/${s.start.day}～${s.end.month}/${s.end.day}'
                '${s.phase == null ? '' : ' · ${s.phase!.name}'}',
              ),
              subtitle: Text(
                [
                  s.kcal == null ? '熱量 —' : '熱量 ${s.kcal!.round()}',
                  s.proteinPerKg == null
                      ? '蛋白質 —'
                      : '蛋白質 ${fmtNum(s.proteinPerKg, maxDecimals: 2)} g/kg',
                  '紀錄 ${s.foodDays} 天',
                  '肌酸 ${s.creatineDays} 天',
                ].join(' · '),
              ),
              trailing: Text(
                '體重 ${kg(s.weightChange)}\n'
                '脂肪 ${kg(s.fatMassChange)} · 除脂 ${kg(s.leanMassChange)}',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
