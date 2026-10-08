import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analysis/phase_summary.dart' show kKcalTolerance;
import '../analysis/tdee.dart';
import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/phase_repository.dart';
import '../data/profile_repository.dart';
import '../data/template_repository.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/undo_snackbar.dart';
import 'food_entry_sheet.dart';
import 'templates_screen.dart';

/// 單日飲食：總量（對照階段目標與 TDEE）、一鍵 +1 與打勾、依餐別分組的紀錄。
class FoodScreen extends StatefulWidget {
  const FoodScreen({
    super.key,
    required this.repository,
    required this.templates,
    required this.checks,
    required this.phases,
    required this.profile,
  });

  final FoodRepository repository;
  final TemplateRepository templates;
  final CheckRepository checks;
  final PhaseRepository phases;
  final ProfileRepository profile;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  late DateTime _day;
  late Stream<List<FoodEntry>> _entries;
  late Stream<Set<CheckItem>> _checks;
  late Stream<Phase?> _phase;
  late final Stream<List<MealTemplate>> _pinned;
  late final Stream<Profile?> _profile;

  /// 滑掉的項目要立刻從畫面消失（Dismissible 的要求），不等資料庫 stream 更新。
  final _hidden = <int>{};

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _pinned = widget.templates.watchPinned();
    _profile = widget.profile.watch();
    _setDay(dateOnly(DateTime.now()));
  }

  void _setDay(DateTime day) {
    _day = day;
    _entries = widget.repository.watchDay(day);
    _checks = widget.checks.watchDay(day);
    _phase = widget.phases.watchOn(day);
  }

  bool get _isToday => _day == dateOnly(DateTime.now());

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: dateOnly(DateTime.now()),
    );
    if (picked != null) setState(() => _setDay(picked));
  }

  /// 今天預設現在時間；其他天預設中午。
  DateTime _defaultTime() {
    final now = DateTime.now();
    return _isToday ? now : DateTime(_day.year, _day.month, _day.day, 12);
  }

  Future<void> _add() async {
    final entry = await showFoodEntrySheet(
      context,
      defaultTime: _defaultTime(),
    );
    if (entry != null) await widget.repository.add(entry);
  }

  Future<void> _edit(FoodEntry e) async {
    final entry = await showFoodEntrySheet(
      context,
      defaultTime: e.eatenAt,
      initial: e,
    );
    if (entry != null) await widget.repository.save(entry);
  }

  Future<void> _quickAdd(MealTemplate t) async {
    final id = await widget.templates.addEntryFromTemplate(
      t,
      eatenAt: _defaultTime(),
      meal: MealType.forTime(_defaultTime()),
    );
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已加入「${t.name}」',
      onUndo: () => widget.repository.delete(id),
    );
  }

  Future<void> _delete(FoodEntry e) async {
    setState(() => _hidden.add(e.id));
    await widget.repository.delete(e.id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已刪除 ${e.meal.label} ${e.totalKcal?.round() ?? ''} kcal',
      onUndo: () async {
        await widget.repository.restore(e);
        if (mounted) setState(() => _hidden.remove(e.id));
      },
    );
  }

  void _openTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesScreen(repository: widget.templates),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    final title =
        '${d.month}/${d.day}（${_weekdays[d.weekday - 1]}）${_isToday ? ' · 今天' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('飲食'),
        actions: [
          IconButton(
            onPressed: _openTemplates,
            icon: const Icon(Icons.bolt_outlined),
            tooltip: '一鍵 +1 項目',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() => _setDay(addDays(_day, -1))),
                icon: const Icon(Icons.chevron_left),
                tooltip: '前一天',
              ),
              TextButton(onPressed: _pickDay, child: Text(title)),
              IconButton(
                onPressed: _isToday
                    ? null
                    : () => setState(() => _setDay(addDays(_day, 1))),
                icon: const Icon(Icons.chevron_right),
                tooltip: '後一天',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('記錄'),
      ),
      body: StreamBuilder<List<FoodEntry>>(
        stream: _entries,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = data.where((e) => !_hidden.contains(e.id)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              StreamBuilder<Phase?>(
                stream: _phase,
                builder: (context, phaseSnap) => StreamBuilder<Profile?>(
                  stream: _profile,
                  builder: (context, profileSnap) => _DaySummaryCard(
                    totals: DayTotals.of(entries),
                    phase: phaseSnap.data,
                    tdee: profileSnap.data?.tdeeKcal,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildQuickRow(entries),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '這天還沒有紀錄。\n按「記錄」選餐別、輸入熱量就好。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final meal in MealType.values)
                if (entries.any((e) => e.meal == meal))
                  _MealCard(
                    meal: meal,
                    entries: entries.where((e) => e.meal == meal).toList(),
                    onTap: _edit,
                    onDismissed: _delete,
                  ),
            ],
          );
        },
      ),
    );
  }

  /// 釘選項目一鍵 +1（顯示當天已幾份）與每日打勾。
  Widget _buildQuickRow(List<FoodEntry> entries) {
    return StreamBuilder<List<MealTemplate>>(
      stream: _pinned,
      builder: (context, pinnedSnap) => StreamBuilder<Set<CheckItem>>(
        stream: _checks,
        builder: (context, checkSnap) {
          final pinned = pinnedSnap.data ?? const [];
          final checked = checkSnap.data ?? const {};
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in pinned)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(_pinnedLabel(t, entries)),
                  onPressed: () => _quickAdd(t),
                ),
              for (final item in CheckItem.values)
                FilterChip(
                  label: Text(item.label),
                  selected: checked.contains(item),
                  onSelected: (v) => widget.checks.set(_day, item, v),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _pinnedLabel(MealTemplate t, List<FoodEntry> entries) {
    final count = entries
        .where((e) => e.templateId == t.id)
        .fold<double>(0, (sum, e) => sum + e.servings);
    return count == 0 ? t.name : '${t.name} · ${fmtNum(count, maxDecimals: 2)}';
  }
}

/// 一個餐別的卡片：標題列（餐別、小計）＋各筆紀錄，可點擊編輯、往左滑刪除。
class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.entries,
    required this.onTap,
    required this.onDismissed,
  });

  final MealType meal;
  final List<FoodEntry> entries;
  final void Function(FoodEntry) onTap;
  final void Function(FoodEntry) onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = DayTotals.of(entries);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(meal.label, style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${totals.kcal.round()} kcal', style: muted),
              ],
            ),
          ),
          for (final e in entries)
            Dismissible(
              key: ValueKey(e.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => onDismissed(e),
              child: _EntryTile(entry: e, onTap: () => onTap(e)),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final FoodEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final time = TimeOfDay.fromDateTime(e.eatenAt).format(context);
    final kcal = e.totalKcal == null
        ? '— kcal'
        : '${e.totalKcal!.round()} kcal';
    // 一般紀錄名稱就是餐別，不重複顯示；一鍵 +1 的項目顯示名稱
    final named = e.name != e.meal.label;
    final detail = [
      time,
      if (e.totalProteinG != null) '蛋白質 ${fmtNum(e.totalProteinG!)} g',
      if (e.note != null) e.note!,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    named
                        ? (e.servings == 1
                              ? e.name
                              : '${e.name} ×${fmtNum(e.servings, maxDecimals: 2)}')
                        : kcal,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (named) Text(kcal, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// 當天總量：熱量與蛋白質（有階段目標時顯示進度），以及相對固定 TDEE 的赤字 / 盈餘。
class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.totals, this.phase, this.tdee});

  final DayTotals totals;
  final Phase? phase;
  final double? tdee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final p = phase;
    final kcalTarget = p?.targetKcal ?? tdee;
    final proteinTarget = p?.targetProteinG;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final kcalHit = p?.targetKcal == null
        ? null
        : (totals.kcal - p!.targetKcal!).abs() <=
              p.targetKcal! * kKcalTolerance;
    final proteinHit = proteinTarget == null
        ? null
        : totals.proteinG >= proteinTarget;

    Widget metric({
      required String label,
      required double value,
      required String unit,
      double? target,
      bool? hit,
    }) {
      final color = hit == null
          ? theme.colorScheme.onSurface
          : (hit ? palette.good : palette.bad);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: muted),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${value.round()}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: target == null
                        ? ' $unit'
                        : ' / ${target.round()} $unit',
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (target != null && target > 0)
              LinearProgressIndicator(
                value: math.min(value / target, 1),
                color: hit == null ? theme.colorScheme.primary : color,
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 16,
                    color: palette.phase(p.id),
                  ),
                  const SizedBox(width: 6),
                  Text('階段：${p.name}', style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                metric(
                  label: '熱量',
                  value: totals.kcal,
                  unit: 'kcal',
                  target: kcalTarget,
                  hit: kcalHit,
                ),
                const SizedBox(width: 20),
                metric(
                  label: '蛋白質',
                  value: totals.proteinG,
                  unit: 'g',
                  target: proteinTarget,
                  hit: proteinHit,
                ),
              ],
            ),
            if (tdee != null || totals.missingKcal > 0) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (tdee != null)
                    'TDEE ${tdee!.round()} · ${formatBalance(totals.kcal - tdee!)}',
                  if (totals.missingKcal > 0) '${totals.missingKcal} 筆沒填熱量',
                ].join('　'),
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
