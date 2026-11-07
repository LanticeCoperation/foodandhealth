import 'package:flutter/material.dart';

import '../services/sync_controller.dart';

/// 家人今天吃了多少。唯讀——資料直接從伺服器讀，不寫進本機資料庫。
///
/// 伺服器端靠 RLS 保證只看得到同一家庭的人（infra/supabase/migrations/0002），
/// 而且家人只有 select policy、沒有 update policy，所以也改不動彼此的紀錄。
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.controller});

  final SyncController controller;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late DateTime _day = DateTime.now();
  late Future<List<FamilyDaySummary>> _future = _load();

  Future<List<FamilyDaySummary>> _load() => widget.controller.familyDay(_day);

  void _shiftDay(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label =
        '${_day.year}/${_day.month.toString().padLeft(2, '0')}/'
        '${_day.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('家人')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _shiftDay(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(label, style: theme.textTheme.titleMedium),
                IconButton(
                  onPressed: () => _shiftDay(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<FamilyDaySummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('讀不到家人的資料：${snapshot.error}'),
                    ),
                  );
                }
                final rows = snapshot.data ?? const <FamilyDaySummary>[];
                if (rows.isEmpty) {
                  return const Center(child: Text('還沒有家人的資料'));
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          r.displayName.characters.first,
                        ),
                      ),
                      title: Text(r.isSelf ? '${r.displayName}（我）' : r.displayName),
                      subtitle: Text('${r.entries} 筆紀錄'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${r.kcal.round()} kcal',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '蛋白質 ${r.proteinG.round()} g',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
