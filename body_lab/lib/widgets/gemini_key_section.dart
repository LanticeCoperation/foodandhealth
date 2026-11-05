import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/settings_repository.dart';

/// 去哪裡申請免費的 API key。
const _kApiKeyUrl = 'https://aistudio.google.com/apikey';

/// 設定頁裡的「AI 估熱量」區塊：貼上自己的 Gemini API key。
///
/// key 只存在這支手機的資料庫裡，不會跟著備份匯出。
class GeminiKeySection extends StatefulWidget {
  const GeminiKeySection({super.key, required this.settings});

  final SettingsRepository settings;

  @override
  State<GeminiKeySection> createState() => _GeminiKeySectionState();
}

class _GeminiKeySectionState extends State<GeminiKeySection> {
  final _input = TextEditingController();
  bool _saved = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await widget.settings.geminiApiKey();
    if (!mounted) return;
    setState(() {
      _saved = key != null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await widget.settings.setGeminiApiKey(_input.text);
    if (!mounted) return;
    _input.clear();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已儲存 API key')));
  }

  Future<void> _clear() async {
    await widget.settings.setGeminiApiKey(null);
    if (!mounted) return;
    _input.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_loading) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('AI 估熱量', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            if (_saved)
              Chip(
                label: const Text('已設定'),
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  Icons.check,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '填自己的 Gemini API key，新增飲食時就能讓 AI 估熱量、蛋白質、脂肪。'
          'key 只存在這支手機，不會跟著備份匯出。',
          style: muted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Gemini API key',
            hintText: _saved ? '要換一把再輸入' : 'AIza…',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _save,
              child: const Text('儲存 API key'),
            ),
            const SizedBox(width: 8),
            if (_saved)
              TextButton(onPressed: _clear, child: const Text('清除')),
            const Spacer(),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(_kApiKeyUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('去申請'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('免費額度下，Google 可能會拿你送出的內容改進產品。', style: muted),
      ],
    );
  }
}
