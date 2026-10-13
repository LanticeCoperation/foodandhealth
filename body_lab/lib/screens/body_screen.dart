import 'dart:io';

import 'package:flutter/material.dart';

import '../analysis/energy.dart';
import '../data/activity_repository.dart';
import '../data/body_repository.dart';
import '../data/database.dart';
import '../data/food_repository.dart';
import '../data/phase_repository.dart';
import '../data/profile_repository.dart';
import '../models/body_metric.dart';
import 'body_entry_sheet.dart';
import '../services/health_service.dart';
import '../utils/dates.dart';
import '../theme/app_theme.dart';
import '../utils/trend.dart';

/// 每天的體重 / 體脂 / 脂肪重 / 除脂體重 與 7 日平均。
/// 先顯示本地快取，再背景從健康資料同步。
class BodyScreen extends StatefulWidget {
  const BodyScreen({
    super.key,
    required this.health,
    required this.repository,
    this.activity,
    this.food,
    this.phases,
    this.profile,
    this.extraActions = const [],
  });

  final HealthService health;
  final BodyRepository repository;

  /// 一起同步每日活動消耗（Apple Watch）。
  final ActivityRepository? activity;

  /// 每天卡片下方顯示當天飲食的熱量、蛋白質、脂肪總量。
  final FoodRepository? food;

  /// 攝取的脂肪上限（依當天階段的目標熱量，沒有就用固定 TDEE）。
  final PhaseRepository? phases;
  final ProfileRepository? profile;

  /// AppBar 額外的按鈕（debug 版的示範資料選單）。
  final List<Widget> extraActions;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  late final Stream<List<TrendPoint>> _trend;
  late final Stream<Map<DateTime, DayTotals>> _intake;
  late final Stream<List<Phase>> _phases;
  late final Stream<Profile?> _profile;
  bool _syncing = false;
  HealthAccess? _access;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // 多抓 6 天，讓最舊那天的 7 日平均也是完整的。
    final from = addDays(
      dateOnly(DateTime.now()),
      -(BodyRepository.initialDays - 1 + kMovingAverageDays - 1),
    );
    _trend = widget.repository
        .watchSince(from)
        .map((metrics) => computeTrend(metrics).reversed.toList());
    _intake =
        widget.food?.watchDailyTotalsSince(from) ?? Stream.value(const {});
    _phases = widget.phases?.watchAll() ?? Stream.value(const []);
    _profile = widget.profile?.watch() ?? Stream.value(null);
    _sync();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final access = await widget.health.ensureAccess();
      if (access == HealthAccess.granted) {
        await widget.repository.sync();
        // 活動消耗失敗不影響身體資料（例如使用者只允許讀體重）
        try {
          final days = await widget.activity?.sync();
          debugPrint('[activity] 讀到 $days 天活動消耗');
        } catch (e, st) {
          debugPrint('[activity] 同步失敗：$e\n$st');
        }
      }
      if (!mounted) return;
      setState(() => _access = access);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// 點某一天：Body Lab 手動記錄的可以刪除，其他來源說明要到健康 App 刪。
  Future<void> _openDay(BodyMetric m) async {
    final theme = Theme.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${m.date.month}/${m.date.day} '
                '${m.measuredAt.hour.toString().padLeft(2, '0')}:'
                '${m.measuredAt.minute.toString().padLeft(2, '0')}　'
                '${m.weightKg.toStringAsFixed(1)} kg'
                '${m.bodyFatPercent == null ? '' : '・體脂 ${m.bodyFatPercent!.toStringAsFixed(1)}%'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (m.fromThisApp)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, 'delete'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('刪除這筆'),
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                )
              else
                Text(
                  '這筆來自其他 App（例如體脂計），Body Lab 不能刪除。'
                  '請到健康 App 刪除，再回來同步。',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ),
    );
    if (action != 'delete' || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這筆體重？'),
        content: const Text('會從健康 App 一起刪除（體重與同一時間的體脂率）。'),
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
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.health.deleteBodyMetric(m.measuredAt);
      // 先移除快取再重新同步：如果當天還有其他紀錄，會再顯示那一筆
      await widget.repository.removeDay(m.date);
      await widget.repository.sync(from: m.date);
      messenger.showSnackBar(const SnackBar(content: Text('已刪除')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
    }
  }

  /// 手動記錄：寫進健康資料後，從該筆的日期開始重新同步讀回來。
  Future<void> _addManual() async {
    final entry = await showBodyEntrySheet(context);
    if (entry == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await widget.health.writeBodyMetric(
        time: entry.time,
        weightKg: entry.weightKg,
        bodyFatPercent: entry.bodyFatPercent,
      );
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('沒有寫入權限，請在健康 App 允許 Body Lab 寫入體重與體脂率')),
        );
        return;
      }
      await widget.repository.sync(from: entry.time);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已記錄 ${entry.weightKg.toStringAsFixed(1)} kg'
            '${entry.bodyFatPercent == null ? '' : '、體脂 ${entry.bodyFatPercent!.toStringAsFixed(1)}%'}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('記錄失敗：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // 四個頁籤同時在 IndexedStack 裡，預設 hero tag 會撞在一起
        heroTag: null,
        onPressed: _addManual,
        icon: const Icon(Icons.add),
        label: const Text('記錄體重'),
      ),
      appBar: AppBar(
        title: const Text('身體組成'),
        actions: [
          ...widget.extraActions,
          if (_syncing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _sync,
              icon: const Icon(Icons.sync),
              tooltip: '從健康資料同步',
            ),
        ],
      ),
      body: StreamBuilder<List<TrendPoint>>(
        stream: _trend,
        builder: (context, snapshot) {
          final points = snapshot.data;
          if (points == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (points.isEmpty) {
            return _syncing
                ? const Center(child: CircularProgressIndicator())
                : _problem(fullScreen: true) ?? _noData();
          }
          final banner = _problem(fullScreen: false);
          return StreamBuilder<Map<DateTime, DayTotals>>(
            stream: _intake,
            builder: (context, intakeSnapshot) => StreamBuilder<List<Phase>>(
              stream: _phases,
              builder: (context, phasesSnapshot) => StreamBuilder<Profile?>(
                stream: _profile,
                builder: (context, profileSnapshot) {
                  final intake = intakeSnapshot.data ?? const {};
                  final phases = phasesSnapshot.data ?? const <Phase>[];
                  final today = dateOnly(DateTime.now());
                  double? fatLimit(DateTime day) => fatLimitFor(
                    phase: phases.where((p) => p.contains(day)).firstOrNull,
                    profile: profileSnapshot.data,
                  );
                  // 有飲食資料時，橫幅下面固定一張今天攝取，沒量體重也看得到
                  final header = widget.food == null ? 1 : 2;
                  return RefreshIndicator(
                    onRefresh: _sync,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: points.length + header,
                      itemBuilder: (_, i) {
                        if (i == 0) return banner ?? const SizedBox(height: 4);
                        if (i < header) {
                          return _TodayIntakeCard(
                            intake[today],
                            fatLimit: fatLimit(today),
                          );
                        }
                        final point = points[i - header];
                        final day = point.metric.date;
                        return _DayCard(
                          point: point,
                          // 今天的攝取已經在最上面那張
                          intake: day == today ? null : intake[day],
                          fatLimit: fatLimit(day),
                          onTap: () => _openDay(point.metric),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// 同步失敗或沒權限時的提示；有快取時顯示成列表上方的橫幅。
  Widget? _problem({required bool fullScreen}) {
    final String text;
    final Widget action;

    if (_error != null) {
      text = '同步失敗：$_error';
      action = TextButton(onPressed: _sync, child: const Text('重試'));
    } else {
      switch (_access) {
        case HealthAccess.healthConnectMissing:
        case HealthAccess.healthConnectUpdateRequired:
          final missing = _access == HealthAccess.healthConnectMissing;
          text = missing
              ? '這支手機沒有 Health Connect。Android 13 以下請從 Play 商店安裝。'
              : 'Health Connect 需要更新。';
          action = TextButton(
            onPressed: widget.health.installHealthConnect,
            child: Text(missing ? '安裝' : '更新'),
          );
        case HealthAccess.denied:
          text = '需要體重、體脂、除脂體重的讀取權限。';
          action = TextButton(onPressed: _sync, child: const Text('再次要求'));
        case HealthAccess.granted:
        case null:
          return null;
      }
    }

    if (fullScreen) {
      return _Message(icon: Icons.info_outline, text: text, action: action);
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$text（顯示的是上次同步的資料）',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          action,
        ],
      ),
    );
  }

  Widget _noData() => _Message(
    icon: Icons.monitor_weight_outlined,
    text: Platform.isIOS
        ? '最近 90 天沒有體重資料。\n若健康 App 裡有資料，請到 設定 → 健康 → 資料存取與裝置 '
              '確認已允許本 App 讀取。'
        : '最近 90 天沒有體重資料。\n請確認體脂計 App 有寫入 Health Connect。',
    action: FilledButton(onPressed: _sync, child: const Text('重新同步')),
  );
}

/// 一天一張卡片：日期與量測時間、體重（大字）與 7 日平均，
/// 下方三欄是體脂、脂肪重、除脂體重（顏色和趨勢圖的線一致）；
/// 當天有飲食紀錄時，最下面再一列熱量、蛋白質、脂肪的總攝取。
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.point,
    this.intake,
    this.fatLimit,
    required this.onTap,
  });

  final TrendPoint point;
  final DayTotals? intake;

  /// 當天的脂肪建議上限（g）。
  final double? fatLimit;
  final VoidCallback onTap;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final m = point.metric;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final dev = point.weightDeviation;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${m.date.month}/${m.date.day}（${_weekdays[m.date.weekday - 1]}）',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_two(m.measuredAt.hour)}:${_two(m.measuredAt.minute)}',
                    style: muted,
                  ),
                  if (m.fromThisApp) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('手動', style: theme.textTheme.labelSmall),
                    ),
                  ],
                  const Spacer(),
                  if (point.isWaterOutlier)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: palette.leanMass.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.water_drop,
                            size: 14,
                            color: palette.leanMass,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '水分 ${dev > 0 ? '+' : ''}${dev.toStringAsFixed(1)} kg',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.leanMass,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    m.weightKg.toStringAsFixed(1),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.weight,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('kg', style: muted),
                  ),
                  // 靠右；窄螢幕時截斷而不是溢出
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '7 日平均 ${point.weightAvg.toStringAsFixed(1)} kg',
                        style: muted,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Metric(
                    label: '體脂',
                    value: m.bodyFatPercent == null
                        ? '—'
                        : '${m.bodyFatPercent!.toStringAsFixed(1)}%',
                  ),
                  _Metric(
                    label: '脂肪重',
                    value: _kg(m.fatMassKg),
                    avg: point.fatMassAvg,
                    color: palette.fatMass,
                  ),
                  _Metric(
                    // 推算：體脂計沒寫入，由 體重 × (1 − 體脂%) 算出
                    label: m.leanMassEstimated ? '除脂 · 推算' : '除脂體重',
                    value: _kg(m.leanMassKg),
                    avg: point.leanMassAvg,
                    color: palette.leanMass,
                  ),
                ],
              ),
              if (intake case final t?) ...[
                const Divider(height: 20),
                _IntakeRow(t, fatLimit: fatLimit),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _kg(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1)} kg';
}

/// 列表最上面的今天攝取；今天還沒記飲食時顯示提示。
class _TodayIntakeCard extends StatelessWidget {
  const _TodayIntakeCard(this.totals, {this.fatLimit});

  final DayTotals? totals;

  /// 脂肪建議上限（g）；沒有個人資料也沒有階段時為 null。
  final double? fatLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今天攝取', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (totals case final t?)
              _IntakeRow(t, fatLimit: fatLimit)
            else
              Text(
                '今天還沒有飲食紀錄',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一天的攝取熱量、蛋白質、脂肪總量（顏色和攝取圖表一致）。
class _IntakeRow extends StatelessWidget {
  const _IntakeRow(this.totals, {this.fatLimit});

  final DayTotals totals;

  /// 有值時脂肪下方顯示上限，超過時改成紅字「超過上限」
  /// （脂肪本身的顏色和紅色太接近，只換數值顏色看不出來）。
  final double? fatLimit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final limit = fatLimit;
    final over = limit != null && totals.fatG > limit;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Metric(
          label: '攝取熱量',
          value: _amount(totals.kcal, 'kcal'),
          color: palette.intakeLine,
        ),
        _Metric(
          label: '攝取蛋白質',
          value: _amount(totals.proteinG, 'g'),
          color: palette.protein,
        ),
        _Metric(
          label: '攝取脂肪',
          value: _amount(totals.fatG, 'g'),
          color: palette.fatMass,
          note: limit == null
              ? null
              : '${over ? '超過' : ''}上限 ${limit.round()} g',
          noteColor: over ? palette.bad : null,
        ),
      ],
    );
  }

  /// 總量是 0 代表當天的紀錄都沒填這項，顯示「—」。
  static String _amount(double v, String unit) =>
      v == 0 ? '—' : '${v.round()} $unit';
}

/// 卡片下方的一欄數值：標籤、當天值、7 日平均或補充說明。
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.avg,
    this.note,
    this.noteColor,
    this.color,
  });

  final String label;
  final String value;
  final double? avg;

  /// 數值下方的小字（例如脂肪上限）。
  final String? note;
  final Color? noteColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
          if (avg != null) Text('7日 ${avg!.toStringAsFixed(1)}', style: muted),
          if (note != null)
            Text(
              note!,
              style: noteColor == null
                  ? muted
                  : muted?.copyWith(
                      color: noteColor,
                      fontWeight: FontWeight.w600,
                    ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
