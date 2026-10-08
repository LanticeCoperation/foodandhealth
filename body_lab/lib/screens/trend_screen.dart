import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/daily_dataset.dart';
import '../analysis/energy.dart';
import '../analysis/tdee.dart' show formatBalance;
import '../analysis/overlay_chart.dart';
import '../data/database.dart';
import '../data/profile_repository.dart';
import '../widgets/nutrition_fields.dart';
import '../theme/app_theme.dart';
import '../widgets/phase_style.dart';

/// 疊加趨勢圖：身體組成 7 日平均的變化 + 每日攝取 + 肌酸，下方是區間摘要。
class TrendScreen extends StatefulWidget {
  const TrendScreen({super.key, required this.dataset, required this.profile});

  final DatasetRepository dataset;
  final ProfileRepository profile;

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  static const _ranges = [30, 60, 90];

  int _range = 30;
  late Stream<DailyDataset> _stream;
  late final Stream<Profile?> _profile;
  Set<BodySeries> _series = BodySeries.values.toSet();
  IntakeSeries _intake = IntakeSeries.kcal;

  @override
  void initState() {
    super.initState();
    _stream = widget.dataset.watch(_range);
    _profile = widget.profile.watch();
  }

  void _setRange(int days) {
    setState(() {
      _range = days;
      _stream = widget.dataset.watch(days);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('趨勢')),
      body: StreamBuilder<Profile?>(
        stream: _profile,
        builder: (context, profileSnap) => StreamBuilder<DailyDataset>(
          stream: _stream,
          builder: (context, snapshot) {
            final ds = snapshot.data;
            if (ds == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = profileSnap.data;
            return _buildBody(ds, p == null ? null : EnergyModel(p));
          },
        ),
      ),
    );
  }

  Widget _buildBody(DailyDataset ds, EnergyModel? energy) {
    double? expenditureOf(DayRecord d) => energy?.expenditure(d.activeKcal);
    final overlay = buildOverlay(
      ds,
      series: _series,
      intake: _intake,
      expenditureOf: energy == null ? null : expenditureOf,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _buildControls(),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: overlay.hasBodyData || overlay.hasIntakeData
              ? OverlayChart(
                  data: overlay,
                  intake: _intake,
                  rangeAnnotations: phaseAnnotations(context, overlay),
                )
              : const Center(child: Text('這段期間沒有資料')),
        ),
        const SizedBox(height: 8),
        _Legend(
          series: _series,
          intake: _intake,
          overlay: overlay,
          referenceLabel: overlay.expenditure.isEmpty
              ? null
              : (energy!.usesWatch ? '每日消耗' : 'TDEE'),
        ),
        const SizedBox(height: 16),
        SummaryCard(
          summary: summarize(
            ds.days,
            expenditureOf: energy == null ? null : expenditureOf,
          ),
          title: '最近 $_range 天',
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<int>(
          segments: [
            for (final r in _ranges)
              ButtonSegment(value: r, label: Text('$r 天')),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setRange(s.single),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in BodySeries.values)
              FilterChip(
                label: Text(s.label),
                selected: _series.contains(s),
                onSelected: (v) => setState(() {
                  _series = {..._series};
                  v ? _series.add(s) : _series.remove(s);
                }),
              ),
            const SizedBox(width: 8),
            DropdownButton<IntakeSeries>(
              value: _intake,
              underline: const SizedBox.shrink(),
              items: [
                for (final i in IntakeSeries.values)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      i == IntakeSeries.none ? '攝取：不顯示' : '攝取：${i.label}',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _intake = v!),
            ),
          ],
        ),
      ],
    );
  }
}

/// 各線顏色（來自主題的 AppPalette，深淺色模式各一套）。
Color seriesColor(BuildContext context, BodySeries s) => switch (s) {
  BodySeries.weight => context.palette.weight,
  BodySeries.fatMass => context.palette.fatMass,
  BodySeries.leanMass => context.palette.leanMass,
};

Color intakeColor(BuildContext context) => context.palette.intake;

Color creatineColor(BuildContext context) => context.palette.creatine;

class OverlayChart extends StatelessWidget {
  const OverlayChart({
    super.key,
    required this.data,
    required this.intake,
    this.rangeAnnotations = const [],
    this.intakeReference,
    this.intakeReferenceLabel,
  });

  final OverlayData data;
  final IntakeSeries intake;

  /// 背景色塊（例如實驗階段）。
  final List<VerticalRangeAnnotation> rangeAnnotations;

  /// 攝取量的參考虛線（例如 TDEE、階段目標），單位同 [intake]。
  final double? intakeReference;
  final String? intakeReferenceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall;
    final o = data;
    final span = o.maxY - o.minY;
    final step = span <= 2 ? 0.5 : (span <= 5 ? 1.0 : 2.0);
    final lastX = math.max(o.days.length - 1, 1).toDouble();
    final dateEvery = math.max(1, (o.days.length / 5).ceil());

    // 每條線對應 tooltip 文字；回傳 null 表示這條線不顯示 tooltip。
    final bars = <LineChartBarData>[];
    final labels = <String? Function(FlSpot)>[];

    if (o.expenditure.isNotEmpty) {
      // 每日總消耗：虛線階梯，和熱量柱同一個尺度
      bars.add(
        LineChartBarData(
          spots: [for (final s in o.expenditure) FlSpot(s.x, o.intakeToY(s.y))],
          isStepLineChart: true,
          lineChartStepData: const LineChartStepData(stepDirection: 0.5),
          barWidth: 1.4,
          dashArray: [5, 3],
          color: theme.colorScheme.onSurfaceVariant,
          dotData: const FlDotData(show: false),
        ),
      );
      labels.add((s) => '消耗 ${o.yToIntake(s.y).round()} kcal');
    }

    if (intake != IntakeSeries.none) {
      final color = intakeColor(context);
      bars.add(
        LineChartBarData(
          // 每天畫成一小段水平線 + 底色，像長條圖；前後沒紀錄的單獨一天也看得到。
          spots: [
            for (final s in o.intake)
              if (s != FlSpot.nullSpot) ...[
                FlSpot(s.x - 0.4, o.intakeToY(s.y)),
                FlSpot(s.x + 0.4, o.intakeToY(s.y)),
                FlSpot.nullSpot,
              ],
          ],
          barWidth: 1,
          color: color.withValues(alpha: 0.6),
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.15),
            cutOffY: o.minY,
            applyCutOffY: true,
          ),
        ),
      );
      labels.add(
        (s) => '${intake.label} ${o.yToIntake(s.y).round()} ${intake.unit}',
      );
    }

    for (final MapEntry(key: series, value: spots) in o.lines.entries) {
      final color = seriesColor(context, series);
      final base = o.baselines[series];
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          barWidth: 2.5,
          color: color,
          dotData: const FlDotData(show: false),
        ),
      );
      labels.add(
        (s) => base == null
            ? null
            : '${series.label} ${(base + s.y).toStringAsFixed(1)} kg '
                  '(${_signed(s.y)})',
      );
    }

    if (o.weightDots.isNotEmpty) {
      final color = seriesColor(context, BodySeries.weight);
      bars.add(
        LineChartBarData(
          spots: o.weightDots,
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 2,
              color: color.withValues(alpha: 0.5),
              strokeWidth: 0,
            ),
          ),
        ),
      );
      final base = o.baselines[BodySeries.weight]!;
      labels.add((s) => '當天 ${(base + s.y).toStringAsFixed(1)} kg');
    }

    if (o.creatineX.isNotEmpty) {
      final color = creatineColor(context);
      bars.add(
        LineChartBarData(
          spots: [for (final x in o.creatineX) FlSpot(x, o.markerY)],
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) =>
                FlDotSquarePainter(size: 5, color: color, strokeWidth: 0),
          ),
        ),
      );
      labels.add((_) => '肌酸 ✓');
    }

    final tooltipStyle = theme.textTheme.bodySmall!;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: lastX,
        minY: o.minY,
        maxY: o.maxY,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 0.5),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: theme.colorScheme.outline,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            if (intakeReference != null && intake != IntakeSeries.none)
              HorizontalLine(
                y: o.intakeToY(intakeReference!),
                color: theme.colorScheme.onSurfaceVariant,
                strokeWidth: 1.2,
                dashArray: [6, 4],
                label: HorizontalLineLabel(
                  show: intakeReferenceLabel != null,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  style: small?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  labelResolver: (_) => intakeReferenceLabel ?? '',
                ),
              ),
          ],
        ),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: rangeAnnotations,
        ),
        lineBarsData: bars,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: step,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(_signed(v), style: small),
              ),
            ),
          ),
          // 右軸數字是從左軸換算來的，不會是整齊的數字；改用 tooltip 與參考虛線。
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (v != i || i % dateEvery != 0 || i >= o.days.length) {
                  return const SizedBox.shrink();
                }
                final d = o.days[i];
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${d.month}/${d.day}', style: small),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
            getTooltipItems: (spots) {
              var first = true;
              return [
                for (final s in spots)
                  switch (labels[s.barIndex](s)) {
                    null => null,
                    final text => () {
                      final d = o.days[s.x.round()];
                      final phase = o.phaseSpans
                          .where((p) => p.x1 <= s.x && s.x <= p.x2)
                          .firstOrNull
                          ?.phase;
                      final date =
                          '${d.month}/${d.day}'
                          '${phase == null ? '' : ' · ${phase.name}'}';
                      final prefix = first ? '$date\n' : '';
                      first = false;
                      return LineTooltipItem(
                        '$prefix$text',
                        tooltipStyle.copyWith(
                          color: s.bar.color == Colors.transparent
                              ? theme.colorScheme.onSurface
                              : s.bar.color,
                        ),
                      );
                    }(),
                  },
              ];
            },
          ),
        ),
      ),
    );
  }

  static String _signed(double v) {
    final rounded = (v * 10).round() / 10;
    if (rounded == 0) return '0';
    return '${rounded > 0 ? '+' : ''}${fmtNum(rounded)}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.series,
    required this.intake,
    required this.overlay,
    this.referenceLabel,
  });

  final Set<BodySeries> series;
  final IntakeSeries intake;
  final OverlayData overlay;

  /// 攝取量參考虛線的名稱（例如 TDEE）。
  final String? referenceLabel;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget item(Color color, String text, {bool square = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: square ? 8 : 14, height: square ? 8 : 3, color: color),
        const SizedBox(width: 4),
        Text(text, style: small),
      ],
    );

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final s in BodySeries.values.where(series.contains))
          item(seriesColor(context, s), '${s.label} 7 日平均'),
        if (intake != IntakeSeries.none)
          item(
            intakeColor(context),
            '每日${intake.label}（灰柱${referenceLabel == null ? '' : '，虛線 = $referenceLabel'}）',
          ),
        item(creatineColor(context), '肌酸', square: true),
        for (final p in {
          for (final s in overlay.phaseSpans) s.phase.id: s.phase,
        }.values)
          item(
            phaseColor(context, p).withValues(alpha: 0.5),
            '階段：${p.name}',
            square: true,
          ),
        Text('左軸：相對區間起點的變化 kg', style: small),
      ],
    );
  }
}

/// 區間摘要卡片；階段頁也會用。
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary, required this.title});

  final RangeSummary summary;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;

    String kg(double? v) =>
        v == null ? '—' : '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} kg';
    String num(double? v, String unit) =>
        v == null ? '—' : '${v.round()} $unit';

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            row('體重變化（7 日平均）', kg(s.weightChange)),
            row('脂肪重變化', kg(s.fatMassChange)),
            row('除脂體重變化', kg(s.leanMassChange)),
            const Divider(),
            row('平均熱量', num(s.avgKcal, 'kcal')),
            row('平均蛋白質', num(s.avgProteinG, 'g')),
            if (s.avgBalance != null)
              row('平均熱量差（攝取 − 消耗）', formatBalance(s.avgBalance!)),
            const Divider(),
            row('有量體重', '${s.weighDays} / ${s.totalDays} 天'),
            row('有飲食紀錄', '${s.foodDays} / ${s.totalDays} 天'),
            row('有吃肌酸', '${s.creatineDays} / ${s.totalDays} 天'),
            const SizedBox(height: 4),
            Text('平均攝取只計算有紀錄的天。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
