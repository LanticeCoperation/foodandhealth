import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../analysis/daily_dataset.dart';
import '../analysis/overlay_chart.dart';
import '../analysis/phase_summary.dart';
import '../data/database.dart';
import '../data/phase_repository.dart';
import '../utils/dates.dart';
import '../widgets/nutrition_fields.dart';
import '../widgets/phase_style.dart';
import 'trend_screen.dart';

String _md(DateTime d) => '${d.month}/${d.day}';

String _kgPerWeek(double? v) =>
    v == null ? '—' : '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';

/// 實驗階段列表：進行中的階段、所有階段卡片、階段比較表。
class PhasesScreen extends StatefulWidget {
  const PhasesScreen({super.key, required this.phases, required this.dataset});

  final PhaseRepository phases;
  final DatasetRepository dataset;

  @override
  State<PhasesScreen> createState() => _PhasesScreenState();
}

class _PhasesScreenState extends State<PhasesScreen> {
  late final Stream<PhaseOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.dataset.watchPhaseOverview();
  }

  Future<void> _add(List<Phase> existing) async {
    await showPhaseSheet(
      context,
      defaultStart: suggestPhaseStart(existing, DateTime.now()),
      onSave: (c) => _trySave(c),
    );
  }

  Future<String?> _trySave(PhasesCompanion c, {int? id}) async {
    try {
      await widget.phases.save(c, id: id);
      return null;
    } on PhaseOverlapException catch (e) {
      return e.toString();
    }
  }

  void _open(Phase p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhaseDetailScreen(
          phaseId: p.id,
          phases: widget.phases,
          dataset: widget.dataset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PhaseOverview>(
      stream: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final phases = data?.phases ?? const <Phase>[];
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: data == null ? null : () => _add(phases),
            icon: const Icon(Icons.add),
            label: const Text('新增階段'),
          ),
          body: switch (data) {
            null => const Center(child: CircularProgressIndicator()),
            (phases: [], dataset: _) => const _EmptyPhases(),
            (:final phases, :final dataset?) => _buildList(phases, dataset),
            (phases: _, dataset: null) => const SizedBox.shrink(),
          },
        );
      },
    );
  }

  Widget _buildList(List<Phase> phases, DailyDataset ds) {
    final today = dateOnly(DateTime.now());
    final summaries = [for (final p in phases) summarizePhase(p, ds, today)];
    final comparable = summaries
        .where((s) => s.elapsedDays >= 7)
        .toList()
        .reversed
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (final s in summaries)
          _PhaseCard(summary: s, onTap: () => _open(s.phase)),
        if (comparable.length >= 2) ...[
          const SizedBox(height: 8),
          _ComparisonTable(summaries: comparable),
        ],
      ],
    );
  }
}

class _EmptyPhases extends StatelessWidget {
  const _EmptyPhases();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '還沒有實驗階段。\n\n'
          '一個階段通常 4 週，固定改變一件事（例如蛋白質提高到每天 160 g、'
          '開始吃肌酸），結束後看體重、脂肪重、除脂體重怎麼變。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.summary, required this.onTap});

  final PhaseSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final p = s.phase;
    final r = s.range;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: phaseColor(context, p), width: 6),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p.name, style: theme.textTheme.titleMedium),
                  ),
                  Text(s.status.label, style: muted),
                ],
              ),
              Text(
                '${_md(p.start)}～${_md(p.end)}（${p.lengthDays} 天）',
                style: muted,
              ),
              if (p.hypothesis != null) ...[
                const SizedBox(height: 4),
                Text(
                  p.hypothesis!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (s.status == PhaseStatus.active) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.progress),
                const SizedBox(height: 2),
                Text('第 ${s.elapsedDays} / ${p.lengthDays} 天', style: muted),
              ],
              if (s.status != PhaseStatus.upcoming) ...[
                const SizedBox(height: 8),
                Text(
                  '每週變化（kg）  體重 ${_kgPerWeek(s.perWeek(r.weightChange))}'
                  ' · 脂肪 ${_kgPerWeek(s.perWeek(r.fatMassChange))}'
                  ' · 除脂 ${_kgPerWeek(s.perWeek(r.leanMassChange))}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                _AdherenceChips(summary: s),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 熱量 / 蛋白質 / 肌酸的達標天數。
class _AdherenceChips extends StatelessWidget {
  const _AdherenceChips({required this.summary});

  final PhaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final p = s.phase;
    final days = s.elapsedDays;
    final items = [
      if (s.kcalHitDays != null)
        '熱量 ${fmtNum(p.targetKcal)}±10% 達標 ${s.kcalHitDays}/$days 天',
      if (s.proteinHitDays != null)
        '蛋白質 ≥${fmtNum(p.targetProteinG)}g 達標 ${s.proteinHitDays}/$days 天',
      if (s.creatineDays != null) '肌酸 ${s.creatineDays}/$days 天',
      '飲食紀錄 ${s.range.foodDays}/$days 天',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final text in items)
          Chip(
            label: Text(text),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

/// 階段比較：每週變化率與平均攝取。
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.summaries});

  final List<PhaseSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String num(double? v) => v == null ? '—' : '${v.round()}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('階段比較', style: theme.textTheme.titleMedium),
            Text(
              '組成變化換算成每週（kg / 週），攝取為有紀錄天的平均。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('階段')),
                  DataColumn(label: Text('體重'), numeric: true),
                  DataColumn(label: Text('脂肪'), numeric: true),
                  DataColumn(label: Text('除脂'), numeric: true),
                  DataColumn(label: Text('熱量'), numeric: true),
                  DataColumn(label: Text('蛋白質'), numeric: true),
                ],
                rows: [
                  for (final s in summaries)
                    DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                color: phaseColor(context, s.phase),
                              ),
                              const SizedBox(width: 6),
                              Text(s.phase.name),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(_kgPerWeek(s.perWeek(s.range.weightChange))),
                        ),
                        DataCell(
                          Text(_kgPerWeek(s.perWeek(s.range.fatMassChange))),
                        ),
                        DataCell(
                          Text(_kgPerWeek(s.perWeek(s.range.leanMassChange))),
                        ),
                        DataCell(Text(num(s.range.avgKcal))),
                        DataCell(Text(num(s.range.avgProteinG))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 單一階段：圖表（含前 7 天）、摘要、執行率、假設與心得。
class PhaseDetailScreen extends StatefulWidget {
  const PhaseDetailScreen({
    super.key,
    required this.phaseId,
    required this.phases,
    required this.dataset,
  });

  final int phaseId;
  final PhaseRepository phases;
  final DatasetRepository dataset;

  @override
  State<PhaseDetailScreen> createState() => _PhaseDetailScreenState();
}

class _PhaseDetailScreenState extends State<PhaseDetailScreen> {
  late final Stream<PhaseOverview> _overview;
  IntakeSeries _intake = IntakeSeries.kcal;

  @override
  void initState() {
    super.initState();
    _overview = widget.dataset.watchPhaseOverview();
  }

  Future<void> _edit(Phase p) async {
    await showPhaseSheet(
      context,
      initial: p,
      defaultStart: p.start,
      onSave: (c) async {
        try {
          await widget.phases.save(c, id: p.id);
          return null;
        } on PhaseOverlapException catch (e) {
          return e.toString();
        }
      },
    );
  }

  Future<void> _delete(Phase p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('刪除「${p.name}」？'),
        content: const Text('只會刪除階段設定，飲食與身體資料都會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.phases.delete(p.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PhaseOverview>(
      stream: _overview,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final p = data?.phases.where((p) => p.id == widget.phaseId).firstOrNull;
        final ds = data?.dataset;
        return Scaffold(
          appBar: AppBar(
            title: Text(p?.name ?? '階段'),
            actions: [
              if (p != null) ...[
                IconButton(
                  onPressed: () => _edit(p),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '編輯',
                ),
                IconButton(
                  onPressed: () => _delete(p),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '刪除',
                ),
              ],
            ],
          ),
          body: p == null || ds == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(p, ds),
        );
      },
    );
  }

  Widget _buildBody(Phase p, DailyDataset ds) {
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final s = summarizePhase(p, ds, today);
    // 圖表多顯示階段前 7 天當對照
    final chartTo = p.end.isAfter(today) ? today : p.end;
    final chartDs = ds.slice(addDays(p.start, -7), chartTo);
    final overlay = buildOverlay(
      chartDs,
      series: BodySeries.values.toSet(),
      intake: _intake,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Text(
          '${_md(p.start)}～${_md(p.end)} · ${s.status.label}'
          '${s.status == PhaseStatus.active ? ' · 第 ${s.elapsedDays}/${p.lengthDays} 天' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        if (p.hypothesis != null) ...[
          const SizedBox(height: 8),
          Text('假設', style: theme.textTheme.labelLarge),
          Text(p.hypothesis!),
        ],
        const SizedBox(height: 12),
        if (s.status == PhaseStatus.upcoming)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('階段還沒開始。', textAlign: TextAlign.center),
          )
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: DropdownButton<IntakeSeries>(
              value: _intake,
              underline: const SizedBox.shrink(),
              items: [
                for (final i in IntakeSeries.values)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      i == IntakeSeries.none ? '攝取：不顯示' : '攝取：${i.label}',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _intake = v!),
            ),
          ),
          SizedBox(
            height: 260,
            child: OverlayChart(
              data: overlay,
              intake: _intake,
              rangeAnnotations: phaseAnnotations(context, overlay),
            ),
          ),
          Text(
            '色塊是階段期間，前面 7 天是對照。線條是 7 日平均相對圖表起點的變化。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _AdherenceChips(summary: s),
          const SizedBox(height: 8),
          SummaryCard(summary: s.range, title: '階段期間'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '換算每週：體重 ${_kgPerWeek(s.perWeek(s.range.weightChange))} kg、'
                '脂肪 ${_kgPerWeek(s.perWeek(s.range.fatMassChange))} kg、'
                '除脂 ${_kgPerWeek(s.perWeek(s.range.leanMassChange))} kg',
              ),
            ),
          ),
        ],
        if (p.conclusion != null) ...[
          const SizedBox(height: 8),
          Text('心得', style: theme.textTheme.labelLarge),
          Text(p.conclusion!),
        ],
      ],
    );
  }
}

/// 新增或編輯階段。[onSave] 回傳錯誤訊息（例如日期重疊）時表單不關閉。
Future<void> showPhaseSheet(
  BuildContext context, {
  required DateTime defaultStart,
  required Future<String?> Function(PhasesCompanion) onSave,
  Phase? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PhaseForm(
      initial: initial,
      defaultStart: defaultStart,
      onSave: onSave,
    ),
  );
}

class _PhaseForm extends StatefulWidget {
  const _PhaseForm({
    required this.defaultStart,
    required this.onSave,
    this.initial,
  });

  final DateTime defaultStart;
  final Future<String?> Function(PhasesCompanion) onSave;
  final Phase? initial;

  @override
  State<_PhaseForm> createState() => _PhaseFormState();
}

class _PhaseFormState extends State<_PhaseForm> {
  static const _weekChoices = [2, 4, 6, 8];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _hypothesis;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _conclusion;
  late DateTime _start;
  late DateTime _end;
  late bool _creatine;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name);
    _hypothesis = TextEditingController(text: p?.hypothesis);
    _kcal = TextEditingController(text: fmtNum(p?.targetKcal));
    _protein = TextEditingController(text: fmtNum(p?.targetProteinG));
    _conclusion = TextEditingController(text: p?.conclusion);
    _start = p?.start ?? widget.defaultStart;
    _end = p?.end ?? addDays(_start, kDefaultPhaseDays - 1);
    _creatine = p?.creatine ?? false;
  }

  @override
  void dispose() {
    for (final c in [_name, _hypothesis, _kcal, _protein, _conclusion]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _days => _end.difference(_start).inDays + 1;

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final days = _days;
      _start = picked;
      _end = addDays(picked, days - 1);
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      PhasesCompanion(
        name: Value(_name.text.trim()),
        startDay: Value(dayKey(_start)),
        endDay: Value(dayKey(_end)),
        hypothesis: Value(text(_hypothesis)),
        targetKcal: Value(parseNum(_kcal.text)),
        targetProteinG: Value(parseNum(_protein.text)),
        creatine: Value(_creatine),
        conclusion: Value(text(_conclusion)),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _error = error;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = _days % 7 == 0 ? _days ~/ 7 : null;

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
                widget.initial == null ? '新增階段' : '編輯階段',
                style: theme.textTheme.titleLarge,
              ),
              TextFormField(
                controller: _name,
                autofocus: widget.initial == null,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '名稱',
                  hintText: '例如：高蛋白 + 肌酸',
                  counterText: '',
                ),
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? '請輸入名稱' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickStart,
                      child: Text('開始 ${_start.year}/${_md(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickEnd,
                      child: Text('結束 ${_md(_end)}（$_days 天）'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final w in _weekChoices)
                    ChoiceChip(
                      label: Text('$w 週'),
                      selected: weeks == w,
                      onSelected: (_) =>
                          setState(() => _end = addDays(_start, w * 7 - 1)),
                    ),
                ],
              ),
              TextFormField(
                controller: _hypothesis,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '假設 / 這階段改變什麼',
                  hintText: '例如：蛋白質提高到 160 g，除脂體重會上升',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _kcal,
                      keyboardType: numberKeyboard,
                      decoration: const InputDecoration(
                        labelText: '每日熱量目標',
                        suffixText: 'kcal',
                      ),
                      validator: validateOptionalNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _protein,
                      keyboardType: numberKeyboard,
                      decoration: const InputDecoration(
                        labelText: '每日蛋白質目標',
                        suffixText: 'g',
                      ),
                      validator: validateOptionalNumber,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: _creatine,
                onChanged: (v) => setState(() => _creatine = v),
                title: const Text('這階段每天吃肌酸'),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.initial != null)
                TextFormField(
                  controller: _conclusion,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '心得 / 結論'),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
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
