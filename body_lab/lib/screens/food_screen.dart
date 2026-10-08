import 'package:flutter/material.dart';

import '../data/check_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../analysis/phase_summary.dart' show kKcalTolerance;
import '../data/phase_repository.dart';
import '../data/template_repository.dart';
import '../utils/dates.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/phase_style.dart';
import 'food_entry_sheet.dart';
import 'quick_add_sheet.dart';
import 'templates_screen.dart';

/// 單日飲食紀錄：當日總量、快速列（釘選範本 +1、每日打勾）、依餐別分組的列表。
/// 新增走範本快速輸入；可編輯、長按存成範本、滑動刪除。
class FoodScreen extends StatefulWidget {
  const FoodScreen({
    super.key,
    required this.repository,
    required this.templates,
    required this.checks,
    required this.phases,
  });

  final FoodRepository repository;
  final TemplateRepository templates;
  final CheckRepository checks;
  final PhaseRepository phases;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  late DateTime _day;
  late Stream<List<FoodEntry>> _entries;
  late Stream<Set<CheckItem>> _checks;
  late Stream<Phase?> _phase;
  late final Stream<List<MealTemplate>> _pinned;

  /// 滑掉的項目要立刻從畫面消失（Dismissible 的要求），不等資料庫 stream 更新。
  final _hidden = <int>{};

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _pinned = widget.templates.watchPinned();
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
    final result = await showQuickAddSheet(
      context,
      templates: widget.templates,
      eatenAt: _defaultTime(),
    );
    switch (result) {
      case AddedFromTemplate(:final entryId, :final name):
        _showUndoAdd(entryId, name);
      case WantsCustom(:final name):
        if (mounted) await _addCustom(name);
      case null:
        break;
    }
  }

  Future<void> _addCustom(String? name) async {
    final result = await showFoodEntrySheet(
      context,
      defaultTime: _defaultTime(),
      initialName: name,
    );
    if (result == null) return;
    await widget.repository.add(result.entry);
    if (result.saveAsTemplate) {
      await widget.templates.addFromEntry(result.entry);
    }
  }

  Future<void> _quickAdd(MealTemplate t) async {
    final id = await widget.templates.addEntryFromTemplate(
      t,
      eatenAt: _defaultTime(),
    );
    _showUndoAdd(id, t.name);
  }

  void _showUndoAdd(int entryId, String name) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已加入「$name」'),
          action: SnackBarAction(
            label: '復原',
            onPressed: () => widget.repository.delete(entryId),
          ),
        ),
      );
  }

  Future<void> _edit(FoodEntry e) async {
    final result = await showFoodEntrySheet(
      context,
      defaultTime: e.eatenAt,
      initial: e,
    );
    if (result != null) await widget.repository.save(result.entry);
  }

  Future<void> _showEntryMenu(FoodEntry e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('存成範本'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('刪除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'template':
        await widget.templates.addFromEntry(e.toCompanion(true));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('已存成範本「${e.name}」')));
      case 'edit':
        await _edit(e);
      case 'delete':
        await _delete(e);
    }
  }

  void _openTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatesScreen(repository: widget.templates),
      ),
    );
  }

  Future<void> _delete(FoodEntry e) async {
    setState(() => _hidden.add(e.id));
    await widget.repository.delete(e.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已刪除「${e.name}」'),
          action: SnackBarAction(
            label: '復原',
            onPressed: () async {
              await widget.repository.restore(e);
              if (mounted) setState(() => _hidden.remove(e.id));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    final title =
        '${d.month}/${d.day}（${_weekdays[d.weekday - 1]}）${_isToday ? ' 今天' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('飲食'),
        actions: [
          IconButton(
            onPressed: _openTemplates,
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: '餐點範本',
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
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '新增',
        child: const Icon(Icons.add),
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
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              StreamBuilder<Phase?>(
                stream: _phase,
                builder: (context, phaseSnap) => _TotalsCard(
                  totals: DayTotals.of(entries),
                  phase: phaseSnap.data,
                ),
              ),
              _buildQuickRow(entries),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('這天還沒有紀錄，按 + 新增。', textAlign: TextAlign.center),
                ),
              for (final meal in MealType.values)
                ..._mealSection(
                  meal,
                  entries.where((e) => e.meal == meal).toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _mealSection(MealType meal, List<FoodEntry> entries) {
    if (entries.isEmpty) return const [];
    final theme = Theme.of(context);
    final kcal = DayTotals.of(entries).kcal;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Text(meal.label, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text('${kcal.round()} kcal', style: theme.textTheme.bodySmall),
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
          onDismissed: (_) => _delete(e),
          child: _EntryTile(
            entry: e,
            onTap: () => _edit(e),
            onLongPress: () => _showEntryMenu(e),
          ),
        ),
    ];
  }

  /// 釘選範本一鍵 +1（顯示當天已吃幾份）與每日打勾。
  Widget _buildQuickRow(List<FoodEntry> entries) {
    return StreamBuilder<List<MealTemplate>>(
      stream: _pinned,
      builder: (context, pinnedSnap) => StreamBuilder<Set<CheckItem>>(
        stream: _checks,
        builder: (context, checkSnap) {
          final pinned = pinnedSnap.data ?? const [];
          final checked = checkSnap.data ?? const {};
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in pinned)
                  ActionChip(
                    avatar: const Icon(Icons.add),
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
            ),
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

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final FoodEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final time = TimeOfDay.fromDateTime(e.eatenAt).format(context);
    final macros = [
      if (e.totalProteinG != null) '蛋白質 ${fmtNum(e.totalProteinG!)}g',
      if (e.totalCarbsG != null) '碳水 ${fmtNum(e.totalCarbsG!)}g',
      if (e.totalFatG != null) '脂肪 ${fmtNum(e.totalFatG!)}g',
    ];
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      title: Text(
        e.servings == 1
            ? e.name
            : '${e.name} ×${fmtNum(e.servings, maxDecimals: 2)}',
      ),
      subtitle: Text(
        [time, ...macros, if (e.note != null) e.note!].join(' · '),
      ),
      trailing: Text(
        e.totalKcal == null ? '— kcal' : '${e.totalKcal!.round()} kcal',
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, this.phase});

  final DayTotals totals;

  /// 當天所屬的實驗階段；有目標時顯示「實際 / 目標」，達標變色。
  final Phase? phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = phase;
    final kcalTarget = p?.targetKcal;
    final proteinTarget = p?.targetProteinG;

    Widget stat(String label, double value, {double? target, bool? hit}) {
      final color = hit == null
          ? null
          : (hit ? theme.colorScheme.primary : theme.colorScheme.error);
      return Expanded(
        child: Column(
          children: [
            Text(
              target == null
                  ? '${value.round()}'
                  : '${value.round()} / ${target.round()}',
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 16,
                      color: phaseColor(p),
                    ),
                    const SizedBox(width: 4),
                    Text('階段：${p.name}', style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            Row(
              children: [
                stat(
                  '熱量 kcal',
                  totals.kcal,
                  target: kcalTarget,
                  hit: kcalTarget == null
                      ? null
                      : (totals.kcal - kcalTarget).abs() <=
                            kcalTarget * kKcalTolerance,
                ),
                stat(
                  '蛋白質 g',
                  totals.proteinG,
                  target: proteinTarget,
                  hit: proteinTarget == null
                      ? null
                      : totals.proteinG >= proteinTarget,
                ),
                stat('碳水 g', totals.carbsG),
                stat('脂肪 g', totals.fatG),
              ],
            ),
            if (totals.missingKcal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${totals.missingKcal} 筆沒填熱量，未計入',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
