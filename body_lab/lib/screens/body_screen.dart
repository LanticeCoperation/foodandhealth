import 'dart:io';

import 'package:flutter/material.dart';

import '../data/body_repository.dart';
import '../services/health_service.dart';
import '../utils/dates.dart';
import '../utils/trend.dart';

/// 每天的體重 / 體脂 / 脂肪重 / 除脂體重 與 7 日平均。
/// 先顯示本地快取，再背景從健康資料同步。
class BodyScreen extends StatefulWidget {
  const BodyScreen({
    super.key,
    required this.health,
    required this.repository,
    this.extraActions = const [],
  });

  final HealthService health;
  final BodyRepository repository;

  /// AppBar 額外的按鈕（debug 版的示範資料選單）。
  final List<Widget> extraActions;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  late final Stream<List<TrendPoint>> _trend;
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
      if (access == HealthAccess.granted) await widget.repository.sync();
      if (!mounted) return;
      setState(() => _access = access);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          return RefreshIndicator(
            onRefresh: _sync,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: points.length + 1,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (_, i) => i == 0
                  ? (banner ?? const SizedBox(height: 8))
                  : _DayRow(point: points[i - 1]),
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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

class _DayRow extends StatelessWidget {
  const _DayRow({required this.point});

  final TrendPoint point;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = point.metric;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final dev = point.weightDeviation;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_two(m.date.month)}/${_two(m.date.day)}（${_weekdays[m.date.weekday - 1]}）',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Text(
                '${_two(m.measuredAt.hour)}:${_two(m.measuredAt.minute)}',
                style: muted,
              ),
              const Spacer(),
              if (point.isWaterOutlier) ...[
                Icon(
                  Icons.water_drop,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${dev > 0 ? '+' : ''}${dev.toStringAsFixed(1)} kg',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _ValueLine(
            label: '體重',
            value: '${m.weightKg.toStringAsFixed(1)} kg',
            avg: '${point.weightAvg.toStringAsFixed(1)} kg',
          ),
          _ValueLine(
            label: '體脂',
            value: m.bodyFatPercent == null
                ? '—'
                : '${m.bodyFatPercent!.toStringAsFixed(1)} %',
          ),
          _ValueLine(
            label: '脂肪重',
            value: _kg(m.fatMassKg),
            avg: point.fatMassAvg == null ? null : _kg(point.fatMassAvg),
          ),
          _ValueLine(
            label: '除脂體重',
            value: _kg(m.leanMassKg),
            note: m.leanMassEstimated ? '*推算' : null,
            avg: point.leanMassAvg == null ? null : _kg(point.leanMassAvg),
          ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _kg(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1)} kg';
}

class _ValueLine extends StatelessWidget {
  const _ValueLine({
    required this.label,
    required this.value,
    this.note,
    this.avg,
  });

  final String label;
  final String value;
  final String? note;
  final String? avg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: muted)),
          Text(value, style: theme.textTheme.bodyLarge),
          if (note != null) ...[
            const SizedBox(width: 4),
            Text(note!, style: muted),
          ],
          const Spacer(),
          if (avg != null) Text('7日 $avg', style: muted),
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
