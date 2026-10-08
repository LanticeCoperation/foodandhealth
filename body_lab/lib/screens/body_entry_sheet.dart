import 'package:flutter/material.dart';

import '../utils/dates.dart';
import '../widgets/nutrition_fields.dart';

typedef BodyEntry = ({DateTime time, double weightKg, double? bodyFatPercent});

/// 手動輸入體重（必填）與體脂率（選填），預設現在時間；可改成較早的日期補登。
Future<BodyEntry?> showBodyEntrySheet(BuildContext context) {
  return showModalBottomSheet<BodyEntry>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BodyEntryForm(),
  );
}

class _BodyEntryForm extends StatefulWidget {
  const _BodyEntryForm();

  @override
  State<_BodyEntryForm> createState() => _BodyEntryFormState();
}

class _BodyEntryFormState extends State<_BodyEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  DateTime _time = DateTime.now();

  @override
  void dispose() {
    _weight.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _time = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _time.hour,
        _time.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked == null) return;
    setState(() {
      _time = DateTime(
        _time.year,
        _time.month,
        _time.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  String? _range(String? s, double min, double max, {bool optional = false}) {
    if (optional && (s == null || s.trim().isEmpty)) return null;
    final v = parseNum(s ?? '');
    return v == null || v < min || v > max
        ? '請輸入 ${fmtNum(min)}–${fmtNum(max)}'
        : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_time.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('不能記錄未來的時間')));
      return;
    }
    Navigator.pop(context, (
      time: _time,
      weightKg: parseNum(_weight.text)!,
      bodyFatPercent: parseNum(_bodyFat.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final isToday = dateOnly(_time) == dateOnly(DateTime.now());

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
            Text('記錄體重', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '會寫入 Apple 健康，和體脂計的資料放在一起。'
              '每天以最早一筆為準，起床後量最準。',
              style: muted,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _weight,
              autofocus: true,
              keyboardType: numberKeyboard,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
              decoration: InputDecoration(
                labelText: '體重',
                hintText: '0.0',
                suffixText: 'kg',
                suffixStyle: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              validator: (s) => _range(s, 20, 300),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyFat,
              keyboardType: numberKeyboard,
              decoration: const InputDecoration(
                labelText: '體脂率（選填）',
                suffixText: '%',
              ),
              validator: (s) => _range(s, 2, 70, optional: true),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(isToday ? '今天' : '${_time.month}/${_time.day}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(TimeOfDay.fromDateTime(_time).format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _submit, child: const Text('儲存')),
          ],
        ),
      ),
    );
  }
}
