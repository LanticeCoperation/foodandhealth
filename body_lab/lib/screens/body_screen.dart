import 'dart:io';

import 'package:flutter/material.dart';

import '../services/health_service.dart';
import '../utils/trend.dart';

/// 驗證用列表：每天的體重 / 體脂 / 脂肪重 / 除脂體重 與 7 日平均。
class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key, required this.service});

  final HealthService service;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  bool _loading = true;
  HealthAccess? _access;
  Object? _error;
  List<TrendPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await widget.service.ensureAccess();
      var points = const <TrendPoint>[];
      if (access == HealthAccess.granted) {
        final metrics = await widget.service.fetchDailyMetrics();
        points = computeTrend(metrics).reversed.toList();
      }
      if (!mounted) return;
      setState(() {
        _access = access;
        _points = points;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('身體組成'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: '重新讀取',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: '讀取失敗：$_error',
        action: FilledButton(onPressed: _load, child: const Text('重試')),
      );
    }

    switch (_access) {
      case HealthAccess.healthConnectMissing:
      case HealthAccess.healthConnectUpdateRequired:
        final missing = _access == HealthAccess.healthConnectMissing;
        return _Message(
          icon: Icons.health_and_safety_outlined,
          text: missing
              ? '這支手機沒有 Health Connect。\nAndroid 13 以下請從 Play 商店安裝。'
              : 'Health Connect 需要更新。',
          action: FilledButton(
            onPressed: () async {
              await widget.service.installHealthConnect();
            },
            child: Text(missing ? '安裝 Health Connect' : '更新 Health Connect'),
          ),
        );
      case HealthAccess.denied:
        return _Message(
          icon: Icons.lock_outline,
          text: '需要體重、體脂、除脂體重的讀取權限。',
          action: FilledButton(onPressed: _load, child: const Text('再次要求權限')),
        );
      case HealthAccess.granted:
      case null:
        break;
    }

    if (_points.isEmpty) {
      return _Message(
        icon: Icons.monitor_weight_outlined,
        text: Platform.isIOS
            ? '最近 90 天沒有體重資料。\n若健康 App 裡有資料，請到 設定 → 健康 → 資料存取與裝置 '
                  '確認已允許本 App 讀取。'
            : '最近 90 天沒有體重資料。\n請確認體脂計 App 有寫入 Health Connect。',
        action: FilledButton(onPressed: _load, child: const Text('重新讀取')),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _points.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _DayRow(point: _points[i]),
      ),
    );
  }
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
