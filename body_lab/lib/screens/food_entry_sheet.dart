import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../widgets/nutrition_fields.dart';

typedef FoodEntryResult = ({FoodEntriesCompanion entry, bool saveAsTemplate});

/// 新增或編輯一筆飲食紀錄。按儲存回傳 companion（編輯時含原本的 id），取消回傳 null。
/// 新增時可勾「同時存成範本」。
Future<FoodEntryResult?> showFoodEntrySheet(
  BuildContext context, {
  required DateTime defaultTime,
  FoodEntry? initial,
  String? initialName,
}) {
  return showModalBottomSheet<FoodEntryResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FoodEntryForm(
      defaultTime: defaultTime,
      initial: initial,
      initialName: initialName,
    ),
  );
}

class _FoodEntryForm extends StatefulWidget {
  const _FoodEntryForm({
    required this.defaultTime,
    this.initial,
    this.initialName,
  });

  final DateTime defaultTime;
  final FoodEntry? initial;
  final String? initialName;

  @override
  State<_FoodEntryForm> createState() => _FoodEntryFormState();
}

class _FoodEntryFormState extends State<_FoodEntryForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _eatenAt;
  late MealType _meal;
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final NutritionControllers _nutrition;
  late final TextEditingController _note;
  bool _saveAsTemplate = false;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _eatenAt = e?.eatenAt ?? widget.defaultTime;
    _meal = e?.meal ?? MealType.forTime(_eatenAt);
    _name = TextEditingController(text: e?.name ?? widget.initialName);
    _servings = TextEditingController(
      text: fmtNum(e?.servings ?? 1, maxDecimals: 2),
    );
    _nutrition = NutritionControllers(
      kcal: e?.kcal,
      protein: e?.proteinG,
      carbs: e?.carbsG,
      fat: e?.fatG,
    );
    _note = TextEditingController(text: e?.note);
  }

  @override
  void dispose() {
    for (final c in [_name, _servings, _note]) {
      c.dispose();
    }
    _nutrition.dispose();
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
    final note = _note.text.trim();
    final initial = widget.initial;
    final entry = FoodEntriesCompanion(
      // 編輯時整筆覆蓋，所以原本的 id / createdAt / templateId 都要帶回去。
      id: initial == null ? const Value.absent() : Value(initial.id),
      createdAt: initial == null
          ? const Value.absent()
          : Value(initial.createdAt),
      templateId: Value(initial?.templateId),
      eatenAt: Value(_eatenAt),
      meal: Value(_meal),
      name: Value(_name.text.trim()),
      servings: Value(parseNum(_servings.text)!),
      kcal: Value(_nutrition.kcalValue),
      proteinG: Value(_nutrition.proteinValue),
      carbsG: Value(_nutrition.carbsValue),
      fatG: Value(_nutrition.fatValue),
      note: Value(note.isEmpty ? null : note),
    );
    Navigator.pop(context, (
      entry: entry,
      saveAsTemplate: _isNew && _saveAsTemplate,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(_eatenAt).format(context);

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
                _isNew ? '自訂飲食' : '編輯飲食',
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
                      autofocus: _isNew && widget.initialName == null,
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
                      validator: validateServings,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              NutritionFields(controllers: _nutrition),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: '備註'),
              ),
              if (_isNew)
                CheckboxListTile(
                  value: _saveAsTemplate,
                  onChanged: (v) => setState(() => _saveAsTemplate = v!),
                  title: const Text('同時存成範本'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
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
