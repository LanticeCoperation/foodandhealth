import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/template_repository.dart';
import '../utils/dates.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/undo_snackbar.dart';

/// 項目的一行摘要：每份營養、預設份量、使用次數。
String templateSummary(MealTemplate t) {
  return [
    if (t.kcal != null) '${fmtNum(t.kcal)} kcal',
    if (t.proteinG != null) '蛋白質 ${fmtNum(t.proteinG)}g',
    if (t.defaultServings != 1)
      '預設 ${fmtNum(t.defaultServings, maxDecimals: 2)} 份',
    if (t.useCount > 0) '用過 ${t.useCount} 次',
  ].join(' · ');
}

/// 「快速」分頁：一鍵 +1 項目（例如蛋白粉）。每列按 +1 記一份到今天，
/// 顯示今天已幾份；點列編輯、置頂排序、往左滑刪除。
class QuickScreen extends StatefulWidget {
  const QuickScreen({super.key, required this.templates, required this.food});

  final TemplateRepository templates;

  /// 今天的紀錄（算已幾份）與復原加入。
  final FoodRepository food;

  @override
  State<QuickScreen> createState() => _QuickScreenState();
}

class _QuickScreenState extends State<QuickScreen> {
  late final Stream<List<MealTemplate>> _templates;
  late final Stream<List<FoodEntry>> _today;
  final _hidden = <int>{};

  TemplateRepository get _repo => widget.templates;

  @override
  void initState() {
    super.initState();
    _templates = _repo.watchTemplates();
    _today = widget.food.watchDay(dateOnly(DateTime.now()));
  }

  /// 記一份到今天（依現在時間判斷餐別），可復原。
  Future<void> _quickAdd(MealTemplate t) async {
    final now = DateTime.now();
    final id = await _repo.addEntryFromTemplate(
      t,
      eatenAt: now,
      meal: MealType.forTime(now),
    );
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已加入「${t.name}」',
      onUndo: () => widget.food.delete(id),
    );
  }

  /// 今天這個項目記了幾份；0 份回傳 null。
  static String? _todayLabel(MealTemplate t, List<FoodEntry> entries) {
    final count = entries
        .where((e) => e.templateId == t.id)
        .fold<double>(0, (sum, e) => sum + e.servings);
    return count == 0 ? null : '今天 ${fmtNum(count, maxDecimals: 2)} 份';
  }

  Future<void> _add() async {
    final t = await showTemplateSheet(context);
    if (t != null) await _repo.add(t);
  }

  Future<void> _edit(MealTemplate t) async {
    final updated = await showTemplateSheet(context, initial: t);
    if (updated != null) await _repo.update(t.id, updated);
  }

  Future<void> _archive(MealTemplate t) async {
    setState(() => _hidden.add(t.id));
    await _repo.archive(t.id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已刪除「${t.name}」',
      onUndo: () async {
        await _repo.unarchive(t.id);
        if (mounted) setState(() => _hidden.remove(t.id));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('快速')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '新增項目',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<MealTemplate>>(
        stream: _templates,
        builder: (context, snapshot) => StreamBuilder<List<FoodEntry>>(
          stream: _today,
          builder: (context, todaySnap) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final today = todaySnap.data ?? const <FoodEntry>[];
            final list = data.where((t) => !_hidden.contains(t.id)).toList();
            if (list.isEmpty) {
              return const Center(child: Text('還沒有項目，按 + 新增。'));
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '按 +1 就記一份到今天（例如蛋白粉）；點項目可以編輯。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                for (final t in list)
                  Dismissible(
                    key: ValueKey(t.id),
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
                    onDismissed: (_) => _archive(t),
                    child: ListTile(
                      leading: IconButton(
                        onPressed: () => _repo.setPinned(t.id, !t.pinned),
                        icon: Icon(
                          t.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        ),
                        tooltip: t.pinned ? '取消置頂' : '置頂',
                      ),
                      title: Text(t.name),
                      subtitle: Text(templateSummary(t)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_todayLabel(t, today) case final label?)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          IconButton.filledTonal(
                            onPressed: () => _quickAdd(t),
                            icon: const Icon(Icons.add),
                            tooltip: '+1',
                          ),
                        ],
                      ),
                      onTap: () => _edit(t),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 新增或編輯範本，回傳要寫入的欄位；取消回傳 null。
Future<MealTemplatesCompanion?> showTemplateSheet(
  BuildContext context, {
  MealTemplate? initial,
}) {
  return showModalBottomSheet<MealTemplatesCompanion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TemplateForm(initial: initial),
  );
}

class _TemplateForm extends StatefulWidget {
  const _TemplateForm({this.initial});

  final MealTemplate? initial;

  @override
  State<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends State<_TemplateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final NutritionControllers _nutrition;

  late bool _pinned;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name);
    _servings = TextEditingController(
      text: fmtNum(t?.defaultServings ?? 1, maxDecimals: 2),
    );
    _nutrition = NutritionControllers(
      kcal: t?.kcal,
      protein: t?.proteinG,
      carbs: t?.carbsG,
      fat: t?.fatG,
    );
    _pinned = t?.pinned ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    _nutrition.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MealTemplatesCompanion(
        name: Value(_name.text.trim()),
        // 一鍵 +1 一律依加入時間判斷餐別
        meal: const Value(null),
        defaultServings: Value(parseNum(_servings.text)!),
        kcal: Value(_nutrition.kcalValue),
        proteinG: Value(_nutrition.proteinValue),
        carbsG: Value(_nutrition.carbsValue),
        fatG: Value(_nutrition.fatValue),
        pinned: Value(_pinned),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                widget.initial == null ? '新增項目' : '編輯項目',
                style: Theme.of(context).textTheme.titleLarge,
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
                    width: 96,
                    child: TextFormField(
                      controller: _servings,
                      keyboardType: numberKeyboard,
                      decoration: const InputDecoration(
                        labelText: '預設份量',
                        suffixText: '份',
                      ),
                      validator: validateServings,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              NutritionFields(controllers: _nutrition),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
                title: const Text('置頂'),
                contentPadding: EdgeInsets.zero,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('儲存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
