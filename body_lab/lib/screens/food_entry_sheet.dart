import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../services/food_ai.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/sheet_title.dart';

/// 問 AI 一份食物的營養；失敗時丟 [FoodAiException]。
typedef AskFoodAi = Future<FoodNutrition> Function(String description);

/// 新增或編輯一筆飲食：選餐別、輸入熱量（蛋白質、脂肪選填）。
/// 按儲存回傳要寫入的 companion（編輯時含原本的 id），取消回傳 null。
/// 編輯時有 [onDelete] 會顯示「刪除」按鈕：關閉表單後呼叫它。
/// 給了 [askAi] 才會顯示「用 AI 估熱量」。
Future<FoodEntriesCompanion?> showFoodEntrySheet(
  BuildContext context, {
  required DateTime defaultTime,
  FoodEntry? initial,
  VoidCallback? onDelete,
  AskFoodAi? askAi,
}) {
  return showModalBottomSheet<FoodEntriesCompanion>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FoodEntryForm(
      defaultTime: defaultTime,
      initial: initial,
      onDelete: onDelete,
      askAi: askAi,
    ),
  );
}

class _FoodEntryForm extends StatefulWidget {
  const _FoodEntryForm({
    required this.defaultTime,
    this.initial,
    this.onDelete,
    this.askAi,
  });

  final DateTime defaultTime;
  final FoodEntry? initial;
  final VoidCallback? onDelete;
  final AskFoodAi? askAi;

  @override
  State<_FoodEntryForm> createState() => _FoodEntryFormState();
}

class _FoodEntryFormState extends State<_FoodEntryForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _eatenAt;
  late MealType _meal;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _fat;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _eatenAt = e?.eatenAt ?? widget.defaultTime;
    _meal = e?.meal ?? MealType.forTime(_eatenAt);
    // 畫面上一律顯示這一筆的總量（每份 × 份量）
    _kcal = TextEditingController(text: fmtNum(e?.totalKcal));
    _protein = TextEditingController(text: fmtNum(e?.totalProteinG));
    _fat = TextEditingController(text: fmtNum(e?.totalFatG));
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    _fat.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 問 AI 之後把估計值填進欄位；使用者可以再改，按儲存才會寫進去。
  Future<void> _askAi() async {
    final n = await showDialog<FoodNutrition>(
      context: context,
      builder: (_) =>
          _AiLookupDialog(askAi: widget.askAi!, note: _note.text.trim()),
    );
    if (n == null || !mounted) return;
    setState(() {
      _kcal.text = fmtNum(n.kcal);
      _protein.text = fmtNum(n.proteinG);
      _fat.text = fmtNum(n.fatG);
    });
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
    final fat = parseNum(_fat.text);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();

    if (e == null) {
      Navigator.pop(
        context,
        FoodEntriesCompanion.insert(
          eatenAt: _eatenAt,
          meal: _meal,
          name: _meal.label,
          kcal: Value(kcal),
          proteinG: Value(protein),
          fatG: Value(fat),
          note: Value(note),
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
            fatG: Value(fat == null ? null : fat / s),
            note: Value(note),
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
            SheetTitle(widget.initial == null ? '新增飲食' : '編輯飲食'),
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
            if (widget.askAi != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filledTonal(
                  onPressed: _askAi,
                  tooltip: '用 AI 估熱量',
                  icon: const Icon(Icons.auto_awesome, size: 20),
                ),
              ),
            TextFormField(
              controller: _kcal,
              autofocus: widget.initial == null,
              keyboardType: numberKeyboard,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
              decoration: InputDecoration(
                labelText: '熱量',
                hintText: '0',
                suffixText: 'kcal',
                suffixStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              validator: (s) {
                final v = parseNum(s ?? '');
                return v == null || v < 0 ? '請輸入熱量' : null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _protein,
                    keyboardType: numberKeyboard,
                    decoration: const InputDecoration(
                      labelText: '蛋白質（選填）',
                      suffixText: 'g',
                    ),
                    validator: validateOptionalNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _fat,
                    keyboardType: numberKeyboard,
                    decoration: const InputDecoration(
                      labelText: '脂肪（選填）',
                      suffixText: 'g',
                    ),
                    validator: validateOptionalNumber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '備註（選填）',
                hintText: '例如：半碗飯、少糖、外食',
              ),
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
            if (widget.onDelete != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDelete!();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('刪除這筆'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 輸入一句食物描述，問 AI 要熱量 / 蛋白質 / 脂肪。
/// 查到了就 pop 出 [FoodNutrition]，失敗就留在原地顯示訊息。
class _AiLookupDialog extends StatefulWidget {
  const _AiLookupDialog({required this.askAi, this.note = ''});

  final AskFoodAi askAi;

  /// 表單上已填的備註，查詢時一起交給 AI 參考。
  final String note;

  @override
  State<_AiLookupDialog> createState() => _AiLookupDialogState();
}

class _AiLookupDialogState extends State<_AiLookupDialog> {
  final _input = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String message;
    try {
      final text = _input.text.trim();
      final n = await widget.askAi(
        widget.note.isEmpty || text.isEmpty ? text : '$text（備註：${widget.note}）',
      );
      if (!mounted) return;
      Navigator.pop(context, n);
      return;
    } on FoodAiException catch (e) {
      message = e.message;
    } catch (e) {
      message = '查詢失敗：$e';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('用 AI 估熱量'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _input,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loading ? null : _submit(),
            decoration: const InputDecoration(
              labelText: '吃了什麼',
              hintText: '一碗滷肉飯',
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.note.isNotEmpty) ...[
            Text(
              '會一併參考備註：${widget.note}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            'AI 給的是估計值，存檔前自己看一下合不合理。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: const Text('查詢'),
        ),
      ],
    );
  }
}
