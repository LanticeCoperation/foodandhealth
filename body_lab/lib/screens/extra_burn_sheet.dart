import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/extra_burn_repository.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/undo_snackbar.dart';

/// 某一天的運動（自訂消耗）：列出已加的，點一筆可編輯、可刪除；下方新增一筆。
Future<void> showExtraBurnSheet(
  BuildContext context, {
  required ExtraBurnRepository repository,
  required DateTime day,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExtraBurnPanel(repository: repository, day: day),
  );
}

class _ExtraBurnPanel extends StatefulWidget {
  const _ExtraBurnPanel({required this.repository, required this.day});

  final ExtraBurnRepository repository;
  final DateTime day;

  @override
  State<_ExtraBurnPanel> createState() => _ExtraBurnPanelState();
}

class _ExtraBurnPanelState extends State<_ExtraBurnPanel> {
  final _formKey = GlobalKey<FormState>();
  final _kcal = TextEditingController();
  final _note = TextEditingController();
  late final Stream<List<ExtraBurn>> _items;

  /// 正在編輯的那筆；null 表示新增。
  ExtraBurn? _editing;

  @override
  void initState() {
    super.initState();
    _items = widget.repository.watchDay(widget.day);
  }

  @override
  void dispose() {
    _kcal.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final note = _note.text.trim();
    final kcal = parseNum(_kcal.text)!;
    final editing = _editing;
    if (editing == null) {
      await widget.repository.add(
        widget.day,
        kcal,
        note: note.isEmpty ? null : note,
      );
    } else {
      await widget.repository.update(
        editing.id,
        kcal,
        note: note.isEmpty ? null : note,
      );
    }
    _resetForm();
  }

  void _startEdit(ExtraBurn b) {
    setState(() => _editing = b);
    _kcal.text = fmtNum(b.kcal);
    _note.text = b.note ?? '';
  }

  void _resetForm() {
    _kcal.clear();
    _note.clear();
    if (!mounted) return;
    setState(() => _editing = null);
    FocusScope.of(context).unfocus();
  }

  Future<void> _delete(ExtraBurn b) async {
    if (_editing?.id == b.id) _resetForm();
    await widget.repository.delete(b.id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已刪除運動 ${b.kcal.round()} kcal',
      onUndo: () => widget.repository.restore(b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final d = widget.day;

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
            Text('運動 · ${d.month}/${d.day}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '記錄 Apple Watch 沒記錄到的運動消耗（例如沒戴錶的游泳、爬山），'
              '會加進當天的每日消耗。手錶已經記錄的運動不要再加，否則會重複計算。',
              style: muted,
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<ExtraBurn>>(
              stream: _items,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (items.isEmpty) return const SizedBox.shrink();
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      for (final b in items)
                        ListTile(
                          dense: true,
                          selected: _editing?.id == b.id,
                          onTap: () => _startEdit(b),
                          leading: const Icon(Icons.directions_run),
                          title: Text(b.note ?? '運動'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${b.kcal.round()} kcal',
                                style: theme.textTheme.titleSmall,
                              ),
                              IconButton(
                                onPressed: () => _delete(b),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: '刪除',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    controller: _kcal,
                    autofocus: true,
                    keyboardType: numberKeyboard,
                    decoration: const InputDecoration(
                      labelText: '消耗',
                      suffixText: 'kcal',
                    ),
                    validator: (s) {
                      final v = parseNum(s ?? '');
                      return v == null || v <= 0 ? '請輸入熱量' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: '備註（選填）',
                      hintText: '例如：游泳',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_editing != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetForm,
                      child: const Text('取消編輯'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(_editing == null ? Icons.add : Icons.check),
                    label: Text(_editing == null ? '加入' : '儲存修改'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
