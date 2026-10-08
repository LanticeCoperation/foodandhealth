import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/template_repository.dart';
import '../widgets/nutrition_fields.dart';

sealed class QuickAddResult {}

/// 已從範本加入一筆，[entryId] 用來復原。
class AddedFromTemplate extends QuickAddResult {
  AddedFromTemplate(this.entryId, this.name);
  final int entryId;
  final String name;
}

/// 改用自訂輸入；[name] 是搜尋框的文字，帶進表單。
class WantsCustom extends QuickAddResult {
  WantsCustom(this.name);
  final String? name;
}

/// 從範本快速新增：搜尋 → 選範本 → 選份量倍率與餐別 → 加入。
Future<QuickAddResult?> showQuickAddSheet(
  BuildContext context, {
  required TemplateRepository templates,
  required DateTime eatenAt,
}) {
  return showModalBottomSheet<QuickAddResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _QuickAddPanel(templates: templates, eatenAt: eatenAt),
    ),
  );
}

class _QuickAddPanel extends StatefulWidget {
  const _QuickAddPanel({required this.templates, required this.eatenAt});

  final TemplateRepository templates;
  final DateTime eatenAt;

  @override
  State<_QuickAddPanel> createState() => _QuickAddPanelState();
}

class _QuickAddPanelState extends State<_QuickAddPanel> {
  static const _servingChoices = [0.5, 1.0, 1.5, 2.0];

  final _search = TextEditingController();
  late Stream<List<MealTemplate>> _results;
  MealTemplate? _selected;
  double _servings = 1;
  late MealType _meal;

  @override
  void initState() {
    super.initState();
    _results = widget.templates.watchTemplates();
    _meal = MealType.forTime(widget.eatenAt);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    setState(() => _results = widget.templates.watchTemplates(query: q));
  }

  void _select(MealTemplate t) {
    setState(() {
      _selected = t;
      _servings = t.defaultServings;
      _meal = t.meal ?? MealType.forTime(widget.eatenAt);
    });
  }

  Future<void> _add() async {
    final t = _selected!;
    final id = await widget.templates.addEntryFromTemplate(
      t,
      eatenAt: widget.eatenAt,
      servings: _servings,
      meal: _meal,
    );
    if (mounted) Navigator.pop(context, AddedFromTemplate(id, t.name));
  }

  void _custom() {
    final q = _search.text.trim();
    Navigator.pop(context, WantsCustom(q.isEmpty ? null : q));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('新增飲食', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _custom,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('自訂輸入'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: _onQuery,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜尋範本',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<MealTemplate>>(
              stream: _results,
              builder: (context, snapshot) {
                final list = snapshot.data ?? const [];
                if (snapshot.hasData && list.isEmpty) {
                  final q = _search.text.trim();
                  return ListView(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(
                          q.isEmpty ? '還沒有範本，自訂輸入一筆' : '找不到「$q」，自訂輸入',
                        ),
                        onTap: _custom,
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    return ListTile(
                      selected: _selected?.id == t.id,
                      leading: Icon(
                        t.pinned ? Icons.push_pin : Icons.restaurant_menu,
                      ),
                      title: Text(t.name),
                      subtitle: Text(templateSummary(t)),
                      onTap: () => _select(t),
                    );
                  },
                );
              },
            ),
          ),
          if (_selected != null) _buildSelection(theme, _selected!),
        ],
      ),
    );
  }

  Widget _buildSelection(ThemeData theme, MealTemplate t) {
    final kcal = t.kcal == null ? null : t.kcal! * _servings;
    final protein = t.proteinG == null ? null : t.proteinG! * _servings;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: _servings > 0.5
                        ? () => setState(() => _servings -= 0.5)
                        : null,
                    icon: const Icon(Icons.remove),
                    tooltip: '減 0.5 份',
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${fmtNum(_servings, maxDecimals: 2)} 份',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: () => setState(() => _servings += 0.5),
                    icon: const Icon(Icons.add),
                    tooltip: '加 0.5 份',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final s in _servingChoices)
                          ChoiceChip(
                            label: Text('×${fmtNum(s)}'),
                            selected: _servings == s,
                            onSelected: (_) => setState(() => _servings = s),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              FilledButton(
                onPressed: _add,
                child: Text(
                  [
                    '加入',
                    if (kcal != null) '${kcal.round()} kcal',
                    if (protein != null) '蛋白質 ${fmtNum(protein)} g',
                  ].join(' · '),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 範本的一行摘要：每份營養、預設份量、餐別、使用次數。
String templateSummary(MealTemplate t) {
  return [
    if (t.kcal != null) '${fmtNum(t.kcal)} kcal',
    if (t.proteinG != null) '蛋白質 ${fmtNum(t.proteinG)}g',
    if (t.carbsG != null) '碳水 ${fmtNum(t.carbsG)}g',
    if (t.fatG != null) '脂肪 ${fmtNum(t.fatG)}g',
    if (t.defaultServings != 1)
      '預設 ${fmtNum(t.defaultServings, maxDecimals: 2)} 份',
    if (t.meal != null) t.meal!.label,
    if (t.useCount > 0) '用過 ${t.useCount} 次',
  ].join(' · ');
}
