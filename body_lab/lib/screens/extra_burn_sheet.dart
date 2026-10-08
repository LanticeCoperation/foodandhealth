import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/extra_burn_repository.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/undo_snackbar.dart';

/// 某一天的自訂消耗：列出已加的、可刪除，下方新增一筆。
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

  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;
    final note = _note.text.trim();
    await widget.repository.add(
      widget.day,
      parseNum(_kcal.text)!,
      note: note.isEmpty ? null : note,
    );
    _kcal.clear();
    _note.clear();
    if (mounted) FocusScope.of(context).unfocus();
  }

  Future<void> _delete(ExtraBurn b) async {
    await widget.repository.delete(b.id);
    if (!mounted) return;
    showUndoSnackBar(
      context,
      '已刪除自訂消耗 ${b.kcal.round()} kcal',
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
            Text(
              '自訂消耗 · ${d.month}/${d.day}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '加 Apple Watch 沒記錄到的活動（例如沒戴錶的游泳、爬山）。'
              '手錶已經記錄的運動不要再加，否則會重複計算。',
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
                          leading: const Icon(Icons.local_fire_department),
                          title: Text(b.note ?? '自訂消耗'),
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
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('加入'),
            ),
          ],
        ),
      ),
    );
  }
}
