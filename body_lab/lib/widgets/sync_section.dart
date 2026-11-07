import 'package:flutter/material.dart';

import '../screens/family_screen.dart';
import '../services/sync_controller.dart';

/// 設定頁裡的「跨裝置同步」區塊。
///
/// 沒設定同步伺服器時整個區塊不顯示（[SyncController.available]）。
class SyncSection extends StatefulWidget {
  const SyncSection({super.key, required this.controller});

  final SyncController controller;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    await widget.controller.signIn(_email.text, _password.text);
    if (!mounted) return;
    if (widget.controller.signedIn) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.available) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('跨裝置同步', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              c.signedIn
                  ? '已登入 ${c.email}'
                  : '登入後，這支手機上的飲食紀錄會同步到你的其他裝置，家人也看得到。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!c.signedIn) ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密碼',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: c.busy ? null : _signIn,
                child: Text(c.busy ? '登入中…' : '登入'),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: c.busy ? null : c.syncNow,
                      child: Text(c.busy ? '同步中…' : '立即同步'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    FamilyScreen(controller: c),
                              ),
                            ),
                      child: const Text('家人'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: c.busy ? null : c.signOut,
                child: const Text('登出'),
              ),
            ],
            if (c.lastMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                c.lastMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
