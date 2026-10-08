import 'package:flutter/material.dart';

/// 資料視覺化與語意用色：圖表線條、達標 / 未達標、實驗階段。
/// 深淺色模式各一套，所有畫面都從這裡取色。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.weight,
    required this.fatMass,
    required this.leanMass,
    required this.intake,
    required this.creatine,
    required this.good,
    required this.bad,
    required this.phases,
    required this.meals,
  });

  final Color weight;
  final Color fatMass;
  final Color leanMass;
  final Color intake;
  final Color creatine;

  /// 達標、往好的方向（脂肪下降、除脂上升）。
  final Color good;

  /// 未達標、往壞的方向。
  final Color bad;

  /// 實驗階段輪流使用的顏色。
  final List<Color> phases;

  /// 餐別顏色，依 早餐 / 午餐 / 晚餐 / 點心 的順序。
  final List<Color> meals;

  static const light = AppPalette(
    weight: Color(0xFF1F6B5A),
    fatMass: Color(0xFFDD6B4D),
    leanMass: Color(0xFF3B78B5),
    intake: Color(0xFFB9A88E),
    creatine: Color(0xFF8B6CC4),
    good: Color(0xFF23936F),
    bad: Color(0xFFD45D43),
    phases: [
      Color(0xFF5FA58C),
      Color(0xFFD8A23A),
      Color(0xFFD7849A),
      Color(0xFF6A97D0),
      Color(0xFF9C88D4),
      Color(0xFF9DAF55),
    ],
    meals: [
      Color(0xFFE09A2D),
      Color(0xFF3F9A68),
      Color(0xFF4C6FBF),
      Color(0xFFC6608A),
    ],
  );

  static const dark = AppPalette(
    weight: Color(0xFF7ED3BA),
    fatMass: Color(0xFFF4A28A),
    leanMass: Color(0xFF8FBAEA),
    intake: Color(0xFF8E816D),
    creatine: Color(0xFFBCA6EC),
    good: Color(0xFF5ED0A8),
    bad: Color(0xFFF2876C),
    phases: [
      Color(0xFF7CC4AA),
      Color(0xFFE9BE62),
      Color(0xFFE9A2B4),
      Color(0xFF8FB4E6),
      Color(0xFFB7A6EC),
      Color(0xFFB8C873),
    ],
    meals: [
      Color(0xFFF0BC62),
      Color(0xFF79C79A),
      Color(0xFF8FA8E8),
      Color(0xFFE79AB8),
    ],
  );

  Color phase(int id) => phases[id % phases.length];

  /// [mealIndex] 是 MealType.index。
  Color meal(int mealIndex) => meals[mealIndex % meals.length];

  /// 熱力圖格子：score -1（差）～ 1（好）。
  Color heat(double score, {bool faded = false}) {
    final alpha = (0.14 + 0.66 * score.abs()) * (faded ? 0.4 : 1);
    return (score >= 0 ? good : bad).withValues(alpha: alpha);
  }

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension AppPaletteContext on BuildContext {
  /// 沒有套用 [buildAppTheme] 時（例如測試裡的 MaterialApp）依深淺色退回預設配色。
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}

const _brand = Color(0xFF1F6B5A);

/// 暖白紙張感的底色 + 深青綠主色。
ColorScheme _scheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(seedColor: _brand, brightness: brightness);
  if (brightness == Brightness.light) {
    return base.copyWith(
      primary: _brand,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCFEADF),
      onPrimaryContainer: const Color(0xFF0A3A2F),
      secondaryContainer: const Color(0xFFE6EFE9),
      onSecondaryContainer: const Color(0xFF1D3B33),
      surface: const Color(0xFFEFEBE4),
      onSurface: const Color(0xFF1E2321),
      onSurfaceVariant: const Color(0xFF5E6662),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFE7E2D9),
      surfaceContainer: const Color(0xFFE2DCD2),
      surfaceContainerHigh: const Color(0xFFDCD6CB),
      surfaceContainerHighest: const Color(0xFFD5CEC2),
      outline: const Color(0xFF8E948F),
      outlineVariant: const Color(0xFFD3CBBE),
      error: const Color(0xFFC2462E),
      errorContainer: const Color(0xFFFBDDD5),
      onErrorContainer: const Color(0xFF5C1606),
    );
  }
  return base.copyWith(
    primary: const Color(0xFF7ED3BA),
    onPrimary: const Color(0xFF00382C),
    primaryContainer: const Color(0xFF1D4E42),
    onPrimaryContainer: const Color(0xFFCFEADF),
    secondaryContainer: const Color(0xFF26332F),
    onSecondaryContainer: const Color(0xFFD2E4DC),
    surface: const Color(0xFF121614),
    onSurface: const Color(0xFFE3E6E3),
    onSurfaceVariant: const Color(0xFFA8B0AC),
    surfaceContainerLowest: const Color(0xFF0D100F),
    surfaceContainerLow: const Color(0xFF181D1B),
    surfaceContainer: const Color(0xFF1C2220),
    surfaceContainerHigh: const Color(0xFF232A27),
    surfaceContainerHighest: const Color(0xFF2B332F),
    outline: const Color(0xFF7D8783),
    outlineVariant: const Color(0xFF333B38),
    error: const Color(0xFFF2876C),
    errorContainer: const Color(0xFF5A1F12),
    onErrorContainer: const Color(0xFFFFDAD1),
  );
}

/// 數字用等寬字，列表與統計對得整齊。
TextTheme _textTheme(TextTheme base) {
  const tabular = [FontFeature.tabularFigures()];
  TextStyle? t(TextStyle? s, {FontWeight? weight}) =>
      s?.copyWith(fontFeatures: tabular, fontWeight: weight ?? s.fontWeight);
  return base.copyWith(
    headlineSmall: t(base.headlineSmall, weight: FontWeight.w700),
    titleLarge: t(base.titleLarge, weight: FontWeight.w700),
    titleMedium: t(base.titleMedium, weight: FontWeight.w600),
    titleSmall: t(base.titleSmall, weight: FontWeight.w600),
    bodyLarge: t(base.bodyLarge),
    bodyMedium: t(base.bodyMedium),
    bodySmall: t(base.bodySmall),
    labelLarge: t(base.labelLarge, weight: FontWeight.w600),
    labelMedium: t(base.labelMedium),
    labelSmall: t(base.labelSmall),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = _scheme(brightness);
  final palette = brightness == Brightness.light
      ? AppPalette.light
      : AppPalette.dark;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = _textTheme(base.textTheme);
  final radius12 = BorderRadius.circular(12);
  final light = brightness == Brightness.light;

  /// 卡片與輸入框的底色：淺色模式白色、深色模式比背景亮一階，和背景拉開層次。
  final raised = light ? Colors.white : scheme.surfaceContainerHigh;

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [palette],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(
        fontSize: 22,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: raised,
      surfaceTintColor: Colors.transparent,
      elevation: light ? 1.5 : 0,
      shadowColor: const Color(0x33000000),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      dividerColor: scheme.outlineVariant,
      labelStyle: text.titleSmall,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: raised,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: radius12),
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      checkmarkColor: scheme.onPrimaryContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: raised,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raised,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius12,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
