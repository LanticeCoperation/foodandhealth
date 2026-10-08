import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';

/// 依時間猜餐別。
MealType mealForTime(DateTime t) {
  final h = t.hour;
  if (h < 10) return MealType.breakfast;
  if (h < 14) return MealType.lunch;
  if (h >= 17 && h < 21) return MealType.dinner;
  return MealType.snack;
}

/// 新增或編輯一筆飲食紀錄。按儲存回傳 companion（編輯時含原本的 id），取消回傳 null。
Future<FoodEntriesCompanion?> showFoodEntrySheet(
  BuildContext context, {
  required DateTime defaultTime,
  FoodEntry? initial,
}) {
  return showModalBottomSheet<FoodEntriesCompanion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _eatenAt = e?.eatenAt ?? widget.defaultTime;
    _meal = e?.meal ?? mealForTime(_eatenAt);
    _name = TextEditingController(text: e?.name);
    _servings = TextEditingController(text: _fmt(e?.servings ?? 1));
    _kcal = TextEditingController(text: _fmt(e?.kcal));
    _protein = TextEditingController(text: _fmt(e?.proteinG));
    _carbs = TextEditingController(text: _fmt(e?.carbsG));
    _fat = TextEditingController(text: _fmt(e?.fatG));
    _note = TextEditingController(text: e?.note);
  }

  @override
  void dispose() {
    for (final c in [_name, _servings, _kcal, _protein, _carbs, _fat, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  static double? _parse(String s) => double.tryParse(s.trim());

  String? _validateOptionalNumber(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final v = _parse(s);
    return v == null || v < 0 ? '請輸入數字' : null;
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
    final note = _note.text.trim();
    final initial = widget.initial;
    Navigator.pop(
      context,
      FoodEntriesCompanion(
        id: initial == null ? const Value.absent() : Value(initial.id),
        createdAt: initial == null
            ? const Value.absent()
            : Value(initial.createdAt),
        eatenAt: Value(_eatenAt),
        meal: Value(_meal),
        name: Value(_name.text.trim()),
        servings: Value(_parse(_servings.text)!),
        kcal: Value(_parse(_kcal.text)),
        proteinG: Value(_parse(_protein.text)),
        carbsG: Value(_parse(_carbs.text)),
        fatG: Value(_parse(_fat.text)),
        note: Value(note.isEmpty ? null : note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(_eatenAt).format(context);
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    Widget numberField(TextEditingController c, String label, String unit) =>
        Expanded(
          child: TextFormField(
            controller: c,
            keyboardType: numberKeyboard,
            decoration: InputDecoration(labelText: label, suffixText: unit),
            validator: _validateOptionalNumber,
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initial == null ? '新增飲食' : '編輯飲食',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<MealType>(
                segments: [
                  for (final m in MealType.values)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_meal},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _meal = s.single),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _name,
                      autofocus: widget.initial == null,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: '名稱',
                        counterText: '',
                      ),
                      validator: (s) =>
                          (s == null || s.trim().isEmpty) ? '請輸入名稱' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: TextFormField(
                      controller: _servings,
                      keyboardType: numberKeyboard,
                      decoration: const InputDecoration(
                        labelText: '份量',
                        suffixText: '份',
                      ),
                      validator: (s) {
                        final v = _parse(s ?? '');
                        return v == null || v <= 0 ? '>0' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('每份營養（可留空）', style: Theme.of(context).textTheme.labelMedium),
              Row(
                children: [
                  numberField(_kcal, '熱量', 'kcal'),
                  const SizedBox(width: 12),
                  numberField(_protein, '蛋白質', 'g'),
                ],
              ),
              Row(
                children: [
                  numberField(_carbs, '碳水', 'g'),
                  const SizedBox(width: 12),
                  numberField(_fat, '脂肪', 'g'),
                ],
              ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: '備註'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(time),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _submit, child: const Text('儲存')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
