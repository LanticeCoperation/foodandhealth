import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../widgets/nutrition_fields.dart';

/// 新增或編輯一筆飲食：選餐別、輸入熱量（蛋白質選填）。
/// 按儲存回傳要寫入的 companion（編輯時含原本的 id），取消回傳 null。
Future<FoodEntriesCompanion?> showFoodEntrySheet(
  BuildContext context, {
  required DateTime defaultTime,
  FoodEntry? initial,
}) {
  return showModalBottomSheet<FoodEntriesCompanion>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FoodEntryForm(defaultTime: defaultTime, initial: initial),
  );
}

class _FoodEntryForm extends StatefulWidget {
  const _FoodEntryForm({required this.defaultTime, this.initial});

  final DateTime defaultTime;
  final FoodEntry? initial;

  @override
  State<_FoodEntryForm> createState() => _FoodEntryFormState();
}

class _FoodEntryFormState extends State<_FoodEntryForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _eatenAt;
  late MealType _meal;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _eatenAt = e?.eatenAt ?? widget.defaultTime;
    _meal = e?.meal ?? MealType.forTime(_eatenAt);
    // 畫面上一律顯示這一筆的總量（每份 × 份量）
    _kcal = TextEditingController(text: fmtNum(e?.totalKcal));
    _protein = TextEditingController(text: fmtNum(e?.totalProteinG));
  }

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eatenAt),
    );
    if (picked == null) return;
    setState(() {
      _eatenAt = DateTime(
        _eatenAt.year,
        _eatenAt.month,
        _eatenAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final e = widget.initial;
    final kcal = parseNum(_kcal.text)!;
    final protein = parseNum(_protein.text);

    if (e == null) {
      Navigator.pop(
        context,
        FoodEntriesCompanion.insert(
          eatenAt: _eatenAt,
          meal: _meal,
          name: _meal.label,
          kcal: Value(kcal),
          proteinG: Value(protein),
        ),
      );
      return;
    }

    // 編輯：保留份量倍率（例如蛋白粉 ×2），把總量換回每份；
    // 名稱原本是餐別的，跟著新餐別改；其他欄位原樣帶回（replace 會整筆覆蓋）。
    final s = e.servings;
    Navigator.pop(
      context,
      e
          .copyWith(
            eatenAt: _eatenAt,
            meal: _meal,
            name: e.name == e.meal.label ? _meal.label : e.name,
            kcal: Value(kcal / s),
            proteinG: Value(protein == null ? null : protein / s),
          )
          .toCompanion(true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = TimeOfDay.fromDateTime(_eatenAt).format(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? '新增飲食' : '編輯飲食',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SegmentedButton<MealType>(
              segments: [
                for (final m in MealType.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_meal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _meal = s.single),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _kcal,
              autofocus: widget.initial == null,
              keyboardType: numberKeyboard,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
              decoration: const InputDecoration(
                labelText: '熱量',
                hintText: '0',
                suffixText: 'kcal',
              ),
              validator: (s) {
                final v = parseNum(s ?? '');
                return v == null || v < 0 ? '請輸入熱量' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _protein,
              keyboardType: numberKeyboard,
              decoration: const InputDecoration(
                labelText: '蛋白質（選填）',
                suffixText: 'g',
              ),
              validator: validateOptionalNumber,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(time),
                ),
                const Spacer(),
                FilledButton(onPressed: _submit, child: const Text('儲存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
