import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/family_admin_api.dart';

/// 家庭管理：建家人帳號、加進家庭、改密碼。
///
/// 每個動作都要輸入管理密碼，那是伺服器 `.env` 裡的 `ADMIN_SECRET`。
/// **密碼不會存在這支手機上**，每次當場輸入——存起來的話，手機掉了
/// 等於把建帳號的權限一起送出去。
class FamilyAdminScreen extends StatefulWidget {
  const FamilyAdminScreen({super.key, required this.api});

  final FamilyAdminApi api;

  @override
  State<FamilyAdminScreen> createState() => _FamilyAdminScreenState();
}

class _FamilyAdminScreenState extends State<FamilyAdminScreen> {
  final _secret = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _family = TextEditingController();

  bool _busy = false;
  String? _output;
  String? _error;
  String? _newPassword;

  @override
  void dispose() {
    _secret.dispose();
    _email.dispose();
    _name.dispose();
    _family.dispose();
    super.dispose();
  }

  Future<void> _run(Future<FamilyAdminResult> Function(String secret) action) async {
    if (_secret.text.isEmpty) {
      setState(() => _error = '請先輸入管理密碼');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _output = null;
      _newPassword = null;
    });
    final r = await action(_secret.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _output = r.text;
        _newPassword = r.password;
      } else {
        _error = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('家庭管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _secret,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '管理密碼',
              helperText: '伺服器 .env 裡的 ADMIN_SECRET，不會存在這支手機上',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(widget.api.list),
            child: const Text('看現況'),
          ),

          const Divider(height: 32),
          Text('新增家人', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
            controller: _name,
            decoration: const InputDecoration(
              labelText: '顯示名稱',
              helperText: '家人之間看到的就是這個，留空會用 email 前半段',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _family,
            decoration: const InputDecoration(
              labelText: '家庭名稱',
              helperText: '要加進哪個家庭；留空就只建帳號',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (s) => widget.api.createMember(
                          s,
                          email: _email.text.trim(),
                          name: _name.text.trim(),
                          family: _family.text.trim(),
                        ),
                      ),
                child: const Text('建立帳號'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (s) => widget.api.addMember(
                          s,
                          family: _family.text.trim(),
                          email: _email.text.trim(),
                        ),
                      ),
                child: const Text('加進家庭'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (s) => widget.api.removeMember(
                          s,
                          family: _family.text.trim(),
                          email: _email.text.trim(),
                        ),
                      ),
                child: const Text('移出家庭'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (s) => widget.api.createFamily(s, _family.text.trim()),
                      ),
                child: const Text('建立家庭'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        (s) =>
                            widget.api.setPassword(s, email: _email.text.trim()),
                      ),
                child: const Text('重設密碼'),
              ),
            ],
          ),

          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],

          if (_newPassword != null) ...[
            const SizedBox(height: 24),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '密碼（只會顯示這一次）',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _newPassword!,
                      style: theme.textTheme.titleMedium,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _newPassword!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已複製')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('複製'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],

          if (_output != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _output!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
