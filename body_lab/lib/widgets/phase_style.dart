import 'package:fl_chart/fl_chart.dart' show VerticalRangeAnnotation;
import 'package:flutter/material.dart';

import '../analysis/overlay_chart.dart';
import '../data/database.dart';
import '../theme/app_theme.dart';

/// 階段的代表色（圖表背景、卡片標記）。
Color phaseColor(BuildContext context, Phase p) => context.palette.phase(p.id);

/// 疊加圖上的階段背景色塊。
List<VerticalRangeAnnotation> phaseAnnotations(
  BuildContext context,
  OverlayData o,
) => [
  for (final span in o.phaseSpans)
    VerticalRangeAnnotation(
      x1: span.x1,
      x2: span.x2,
      color: phaseColor(context, span.phase).withValues(alpha: 0.14),
    ),
];
