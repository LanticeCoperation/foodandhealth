import 'package:flutter/material.dart';

import '../analysis/tdee.dart';
import '../data/body_repository.dart';
import '../data/database.dart';
import '../data/profile_repository.dart';
import '../utils/dates.dart';
import '../utils/trend.dart';
import '../widgets/nutrition_fields.dart';

/// 身體頁右上角的入口。
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key, required this.profile, required this.body});

  final ProfileRepository profile;
  final BodyRepository body;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(profile: profile, body: body),
        ),
      ),
      icon: const Icon(Icons.person_outline),
      tooltip: '個人資料與 TDEE',
    );
  }
}

/// 個人資料：性別、年齡、身高、活動量 → 用 Mifflin-St Jeor 算 TDEE 並固定下來。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile, required this.body});

  final ProfileRepository profile;
  final BodyRepository body;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _tdee = TextEditingController();

  Sex _sex = Sex.male;
  ActivityLevel _activity = ActivityLevel.light;
  EnergyMode _mode = EnergyMode.watch;
  Profile? _saved;
  double? _recentWeight;
  bool _loading = true;

  /// 使用者手動改過 TDEE 後，就不再跟著計算值變動。
  bool _tdeeEdited = false;

  int get _year => DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_age, _height, _weight]) {
      c.addListener(_recalculate);
    }
  }

  Future<void> _load() async {
    final saved = await widget.profile.get();
    final today = dateOnly(DateTime.now());
    final metrics = await widget.body.since(addDays(today, -13));
    final recent = rollingAverages(
      metrics,
      from: addDays(today, -6),
      to: today,
    ).values.lastOrNull?.weight;
    if (!mounted) return;

    if (saved != null) {
      _sex = saved.sex;
      _activity = saved.activity;
      _mode = saved.energyMode;
      // 之前手動調整過 TDEE（和當時的計算值不同）就保留
      final then = estimateTdee(
        sex: saved.sex,
        weightKg: saved.weightKg,
        heightCm: saved.heightCm,
        age: saved.ageIn(saved.updatedAt.year),
        activity: saved.activity,
      );
      if (then != saved.tdeeKcal) {
        _tdeeEdited = true;
        _tdee.text = fmtNum(saved.tdeeKcal);
      }
      _age.text = '${saved.ageIn(_year)}';
      _height.text = fmtNum(saved.heightCm);
    }
    final w = recent ?? saved?.weightKg;
    if (w != null) _weight.text = w.toStringAsFixed(1);

    setState(() {
      _saved = saved;
      _recentWeight = recent;
      _loading = false;
    });
    _recalculate();
  }

  @override
  void dispose() {
    for (final c in [_age, _height, _weight, _tdee]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _bmr {
    final age = int.tryParse(_age.text.trim());
    final h = parseNum(_height.text);
    final w = parseNum(_weight.text);
    if (age == null || h == null || w == null) return null;
    return mifflinBmr(sex: _sex, weightKg: w, heightCm: h, age: age);
  }

  double? get _computed {
    final age = int.tryParse(_age.text.trim());
    final h = parseNum(_height.text);
    final w = parseNum(_weight.text);
    if (age == null || h == null || w == null) return null;
    return estimateTdee(
      sex: _sex,
      weightKg: w,
      heightCm: h,
      age: age,
      activity: _activity,
    );
  }

  void _recalculate() {
    if (_tdeeEdited) {
      setState(() {});
      return;
    }
    final v = _computed;
    setState(() => _tdee.text = v == null ? '' : fmtNum(v));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.profile.save(
      sex: _sex,
      birthYear: _year - int.parse(_age.text.trim()),
      heightCm: parseNum(_height.text)!,
      activity: _activity,
      weightKg: parseNum(_weight.text)!,
      tdeeKcal: parseNum(_tdee.text)!,
      energyMode: _mode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _mode == EnergyMode.watch
              ? '已儲存：每日消耗 = 基礎代謝 ${_bmr!.round()} + Apple Watch 活動消耗'
              : 'TDEE 已固定為 ${parseNum(_tdee.text)!.round()} kcal',
        ),
      ),
    );
    Navigator.pop(context);
  }

  String? _validateRange(String? s, double min, double max) {
    final v = parseNum(s ?? '');
    return v == null || v < min || v > max
        ? '請輸入 ${fmtNum(min)}–${fmtNum(max)}'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('個人資料與 TDEE')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_saved != null)
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${_saved!.energyMode == EnergyMode.watch ? '目前：每日消耗 = 基礎代謝 ${mifflinBmr(sex: _saved!.sex, weightKg: _saved!.weightKg, heightCm: _saved!.heightCm, age: _saved!.ageIn(_saved!.updatedAt.year)).round()} + Apple Watch 活動消耗' : '目前固定 TDEE ${_saved!.tdeeKcal.round()} kcal'}'
                          '（${_saved!.updatedAt.month}/${_saved!.updatedAt.day} '
                          '以 ${_saved!.weightKg.toStringAsFixed(1)} kg 計算）',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SegmentedButton<Sex>(
                    segments: [
                      for (final s in Sex.values)
                        ButtonSegment(value: s, label: Text(s.label)),
                    ],
                    selected: {_sex},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) {
                      _sex = v.single;
                      _recalculate();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _age,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '年齡',
                            suffixText: '歲',
                          ),
                          validator: (s) => _validateRange(s, 10, 100),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _height,
                          keyboardType: numberKeyboard,
                          decoration: const InputDecoration(
                            labelText: '身高',
                            suffixText: 'cm',
                          ),
                          validator: (s) => _validateRange(s, 100, 230),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _weight,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(
                      labelText: '體重',
                      suffixText: 'kg',
                      helperText: _recentWeight == null
                          ? '還沒有體重資料，請手動輸入'
                          : '預設是最近的 7 日平均',
                    ),
                    validator: (s) => _validateRange(s, 30, 250),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _mode == EnergyMode.watch ? '活動量（沒有手錶資料的天才用）' : '活動量',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Card(
                    child: Column(
                      children: [
                        for (final a in ActivityLevel.values)
                          ListTile(
                            selected: a == _activity,
                            title: Text('${a.label}（× ${a.factor}）'),
                            subtitle: Text(a.description),
                            trailing: a == _activity
                                ? Icon(
                                    Icons.check_circle,
                                    color: theme.colorScheme.primary,
                                  )
                                : const Icon(Icons.circle_outlined),
                            onTap: () {
                              _activity = a;
                              _recalculate();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _bmr == null
                                ? '填完上面的欄位就會算出 TDEE'
                                : '基礎代謝 ${_bmr!.round()} kcal × ${_activity.factor}'
                                      ' ≈ ${_computed!.round()} kcal',
                            style: muted,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _tdee,
                            keyboardType: numberKeyboard,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            decoration: InputDecoration(
                              labelText: 'TDEE（每日總消耗）',
                              suffixText: 'kcal',
                              suffixStyle: theme.textTheme.titleMedium
                                  ?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                              helperText: _tdeeEdited
                                  ? '已手動調整'
                                  : '可以手動調整，例如依實際體重變化校正',
                            ),
                            onChanged: (_) => _tdeeEdited = true,
                            validator: (s) => _validateRange(s, 800, 6000),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '基礎代謝和 TDEE 存下來後固定使用，不會隨每天體重變動；'
                            '體重變化超過 2–3 kg 時再回來重算。',
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('每日消耗怎麼算', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<EnergyMode>(
                    segments: [
                      for (final m in EnergyMode.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _mode = v.single),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == EnergyMode.watch
                        ? '每天的消耗 = 基礎代謝'
                              '${_bmr == null ? '' : ' ${_bmr!.round()} kcal'}'
                              ' + 當天 Apple Watch 記錄的活動消耗。'
                              '沒戴手錶、沒有資料的天用上面的 TDEE。'
                        : '每天都用上面的固定 TDEE，不看手錶的活動消耗'
                              '（活動量係數已經包含運動）。',
                    style: muted,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('儲存'),
                  ),
                ],
              ),
            ),
    );
  }
}
