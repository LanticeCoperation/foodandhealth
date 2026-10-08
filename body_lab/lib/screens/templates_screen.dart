import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/template_repository.dart';
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

/// 一鍵 +1 項目（例如蛋白粉）：新增、編輯、釘選到飲食頁、滑動刪除。
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, required this.repository});

  final TemplateRepository repository;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late final Stream<List<MealTemplate>> _templates;
  final _hidden = <int>{};

  @override
  void initState() {
    super.initState();
    _templates = widget.repository.watchTemplates();
  }

  Future<void> _add() async {
    final t = await showTemplateSheet(context);
    if (t != null) await widget.repository.add(t);
  }

  Future<void> _edit(MealTemplate t) async {
    final updated = await showTemplateSheet(context, initial: t);
    if (updated != null) await widget.repository.update(t.id, updated);
  }

  Future<void> _archive(MealTemplate t) async {
    setState(() => _hidden.add(t.id));
    await widget.repository.archive(t.id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已刪除「${t.name}」',
      onUndo: () async {
        await widget.repository.unarchive(t.id);
        if (mounted) setState(() => _hidden.remove(t.id));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('一鍵 +1 項目')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: '新增項目',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<MealTemplate>>(
        stream: _templates,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
                  '釘選的項目會出現在飲食頁，按一下就記一份（例如蛋白粉）。',
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
                      onPressed: () =>
                          widget.repository.setPinned(t.id, !t.pinned),
                      icon: Icon(
                        t.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      ),
                      tooltip: t.pinned ? '取消釘選' : '釘選',
                    ),
                    title: Text(t.name),
                    subtitle: Text(templateSummary(t)),
                    onTap: () => _edit(t),
                  ),
                ),
            ],
          );
        },
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
                title: const Text('釘選到飲食頁（一鍵 +1）'),
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
