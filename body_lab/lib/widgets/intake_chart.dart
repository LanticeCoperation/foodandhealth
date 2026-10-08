import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/intake_chart.dart';
import '../theme/app_theme.dart';

/// 攝取圖：每日熱量（柱）、熱量 7 日平均、每日消耗（虛線）用左軸 kcal；
/// 蛋白質、脂肪的每日值（點）與 7 日平均用右軸 g；底部紫色方塊是肌酸。
class IntakeChart extends StatelessWidget {
  const IntakeChart({
    super.key,
    required this.data,
    this.rangeAnnotations = const [],
  });

  final IntakeChartData data;
  final List<VerticalRangeAnnotation> rangeAnnotations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final small = theme.textTheme.labelSmall;
    final d = data;
    final lastX = math.max(d.days.length - 1, 1).toDouble();
    final dateEvery = math.max(1, (d.days.length / 5).ceil());

    final bars = <LineChartBarData>[];
    final labels = <String? Function(FlSpot)>[];

    // 每日熱量：每天一段水平線 + 底色，看起來像長條
    bars.add(
      LineChartBarData(
        spots: [
          for (final s in d.kcal) ...[
            FlSpot(s.x - 0.38, s.y),
            FlSpot(s.x + 0.38, s.y),
            FlSpot.nullSpot,
          ],
        ],
        barWidth: 1,
        color: palette.intake,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: palette.intake.withValues(alpha: 0.45),
        ),
      ),
    );
    labels.add((s) => '熱量 ${s.y.round()} kcal');

    if (d.expenditure.isNotEmpty) {
      bars.add(
        LineChartBarData(
          spots: d.expenditure,
          isStepLineChart: true,
          lineChartStepData: const LineChartStepData(stepDirection: 0.5),
          barWidth: 1.4,
          dashArray: [5, 3],
          color: theme.colorScheme.onSurfaceVariant,
          dotData: const FlDotData(show: false),
        ),
      );
      labels.add((s) => '消耗 ${s.y.round()} kcal');
    }

    bars.add(
      LineChartBarData(
        spots: d.kcalAvg,
        isCurved: true,
        preventCurveOverShooting: true,
        barWidth: 2.5,
        color: palette.intakeLine,
        dotData: const FlDotData(show: false),
      ),
    );
    labels.add((s) => '熱量 7 日平均 ${s.y.round()}');

    bars.add(
      LineChartBarData(
        spots: [for (final s in d.protein) FlSpot(s.x, d.gramsToY(s.y))],
        barWidth: 0,
        color: Colors.transparent,
        dotData: FlDotData(
          getDotPainter: (_, _, _, _) => FlDotCirclePainter(
            radius: 2.2,
            color: palette.protein.withValues(alpha: 0.55),
            strokeWidth: 0,
          ),
        ),
      ),
    );
    labels.add((s) => '蛋白質 ${d.yToGrams(s.y).round()} g');

    bars.add(
      LineChartBarData(
        spots: [for (final s in d.proteinAvg) FlSpot(s.x, d.gramsToY(s.y))],
        isCurved: true,
        preventCurveOverShooting: true,
        barWidth: 2.5,
        color: palette.protein,
        dotData: const FlDotData(show: false),
      ),
    );
    labels.add((s) => '蛋白質 7 日平均 ${d.yToGrams(s.y).round()} g');

    if (d.fat.isNotEmpty) {
      bars.add(
        LineChartBarData(
          spots: [for (final s in d.fat) FlSpot(s.x, d.gramsToY(s.y))],
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 2.2,
              color: palette.fatMass.withValues(alpha: 0.5),
              strokeWidth: 0,
            ),
          ),
        ),
      );
      labels.add((s) => '脂肪 ${d.yToGrams(s.y).round()} g');
      bars.add(
        LineChartBarData(
          spots: [for (final s in d.fatAvg) FlSpot(s.x, d.gramsToY(s.y))],
          isCurved: true,
          preventCurveOverShooting: true,
          barWidth: 2,
          dashArray: [2, 2],
          color: palette.fatMass,
          dotData: const FlDotData(show: false),
        ),
      );
      labels.add((s) => '脂肪 7 日平均 ${d.yToGrams(s.y).round()} g');
    }

    if (d.creatineX.isNotEmpty) {
      final markerY = d.kcalMax * 0.02;
      bars.add(
        LineChartBarData(
          spots: [for (final x in d.creatineX) FlSpot(x, markerY)],
          barWidth: 0,
          color: Colors.transparent,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => FlDotSquarePainter(
              size: 5,
              color: palette.creatine,
              strokeWidth: 0,
            ),
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
        minY: 0,
        maxY: d.kcalMax,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: rangeAnnotations,
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: d.kcalStep,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 0.5),
        ),
        lineBarsData: bars,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: d.kcalStep,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  '${v.round()}',
                  style: small?.copyWith(color: palette.intakeLine),
                ),
              ),
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: d.kcalStep,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  '${d.yToGrams(v).round()}',
                  style: small?.copyWith(color: palette.protein),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (v != i || i % dateEvery != 0 || i >= d.days.length) {
                  return const SizedBox.shrink();
                }
                final day = d.days[i];
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${day.month}/${day.day}', style: small),
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
                      final day =
                          d.days[s.x.round().clamp(0, d.days.length - 1)];
                      final prefix = first ? '${day.month}/${day.day}\n' : '';
                      first = false;
                      return LineTooltipItem(
                        '$prefix$text',
                        tooltipStyle.copyWith(
                          color: s.bar.color != Colors.transparent
                              ? s.bar.color
                              : text.startsWith('脂肪')
                              ? palette.fatMass
                              : text.startsWith('肌酸')
                              ? palette.creatine
                              : palette.protein,
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
}

class IntakeLegend extends StatelessWidget {
  const IntakeLegend({
    super.key,
    required this.hasExpenditure,
    required this.hasFat,
  });

  final bool hasExpenditure;
  final bool hasFat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget item(Color color, String text, {bool box = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: box ? 10 : 14, height: box ? 10 : 3, color: color),
        const SizedBox(width: 4),
        Text(text, style: small),
      ],
    );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(palette.intake, '每日熱量', box: true),
        item(palette.intakeLine, '熱量 7 日平均（左軸 kcal）'),
        if (hasExpenditure)
          item(Theme.of(context).colorScheme.onSurfaceVariant, '虛線：每日消耗'),
        item(palette.protein, '蛋白質（右軸 g）'),
        if (hasFat) item(palette.fatMass, '脂肪（右軸 g，虛線）'),
        item(palette.creatine, '肌酸', box: true),
        Text('線是 7 日平均，點是每日值', style: small),
      ],
    );
  }
}
