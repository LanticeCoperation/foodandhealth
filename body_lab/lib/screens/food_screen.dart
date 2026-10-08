import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/food_repository.dart';
import '../utils/dates.dart';
import 'food_entry_sheet.dart';

/// 單日飲食紀錄：當日總量、依餐別分組的列表，可新增 / 編輯 / 滑動刪除。
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.repository});

  final FoodRepository repository;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  late DateTime _day;
  late Stream<List<FoodEntry>> _entries;

  /// 滑掉的項目要立刻從畫面消失（Dismissible 的要求），不等資料庫 stream 更新。
  final _hidden = <int>{};

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _setDay(dateOnly(DateTime.now()));
  }

  void _setDay(DateTime day) {
    _day = day;
    _entries = widget.repository.watchDay(day);
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
              _TotalsCard(totals: DayTotals.of(entries)),
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
          child: _EntryTile(entry: e, onTap: () => _edit(e)),
        ),
    ];
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final FoodEntry entry;
  final VoidCallback onTap;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final time = TimeOfDay.fromDateTime(e.eatenAt).format(context);
    final macros = [
      if (e.totalProteinG != null) '蛋白質 ${_num(e.totalProteinG!)}g',
      if (e.totalCarbsG != null) '碳水 ${_num(e.totalCarbsG!)}g',
      if (e.totalFatG != null) '脂肪 ${_num(e.totalFatG!)}g',
    ];
    return ListTile(
      onTap: onTap,
      title: Text(e.servings == 1 ? e.name : '${e.name} ×${_num(e.servings)}'),
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
  const _TotalsCard({required this.totals});

  final DayTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleMedium),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                stat('熱量 kcal', '${totals.kcal.round()}'),
                stat('蛋白質 g', '${totals.proteinG.round()}'),
                stat('碳水 g', '${totals.carbsG.round()}'),
                stat('脂肪 g', '${totals.fatG.round()}'),
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
