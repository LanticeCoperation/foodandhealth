import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Gemini Developer API 的 Interactions 端點。
/// （舊的 `:generateContent` 已被官方標為 legacy。）
const kGeminiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/interactions';

/// 請求格式的版本，官方範例固定帶這個標頭。
const kGeminiApiRevision = '2026-05-20';

/// 估個熱量用這個就夠，也是官方標示最快最省的一款。
/// 2026-11-05 實測可用，一次查詢約 5.7 秒。換模型只要改這裡。
const kGeminiModel = 'gemini-3.5-flash-lite';

/// 實測約 5.7 秒，留足夠的餘裕給慢的時候。
const _timeout = Duration(seconds: 30);

/// 查詢失敗時丟出，[message] 可以直接顯示給使用者。
class FoodAiException implements Exception {
  const FoodAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次查詢的結果：這份食物的總量（不是每 100 克）。
class FoodNutrition {
  const FoodNutrition({required this.kcal, this.proteinG, this.fatG});

  final double kcal;
  final double? proteinG;
  final double? fatG;
}

/// 問 Gemini 一份食物大概有多少熱量、蛋白質、脂肪。
///
/// 回來的數字是估計值，一律讓使用者確認過再存。
class FoodAi {
  FoodAi({
    required this.client,
    required this.apiKey,
    this.model = kGeminiModel,
  });

  final http.Client client;
  final String apiKey;
  final String model;

  static const _schema = {
    'type': 'object',
    'properties': {
      'kcal': {'type': 'number', 'description': '這一份的總熱量，單位大卡'},
      'protein_g': {'type': 'number', 'description': '這一份的總蛋白質，單位公克'},
      'fat_g': {'type': 'number', 'description': '這一份的總脂肪，單位公克'},
    },
    'required': ['kcal'],
  };

  String _prompt(String description) =>
      '你是營養估算助手。使用者吃了：$description\n'
      '請估計這「一整份」的總熱量、總蛋白質、總脂肪，不是每 100 公克的值。\n'
      '以台灣常見的份量與做法為準。無法確定時給合理的估計值，不要拒答。';

  Future<FoodNutrition> lookup(String description) async {
    final text = description.trim();
    if (apiKey.trim().isEmpty) {
      throw const FoodAiException('還沒設定 Gemini API key，請到「個人資料與設定」填一次。');
    }
    if (text.isEmpty) {
      throw const FoodAiException('請先描述吃了什麼。');
    }

    final http.Response response;
    try {
      response = await client
          .post(
            Uri.parse(kGeminiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey.trim(),
              'Api-Revision': kGeminiApiRevision,
            },
            body: jsonEncode({
              'model': model,
              'input': _prompt(text),
              'response_format': {
                'type': 'text',
                'mime_type': 'application/json',
                'schema': _schema,
              },
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const FoodAiException('等太久沒回應，請檢查網路後再試一次。');
    } on SocketException {
      throw const FoodAiException('連不上 Gemini，請檢查網路後再試一次。');
    } on http.ClientException {
      throw const FoodAiException('連不上 Gemini，請檢查網路後再試一次。');
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 429:
        throw const FoodAiException('今天的免費額度用完了，等一下再試。');
      // 模型當下負載太高，跟額度、權限都無關，等一下通常就好了。
      case 503:
        throw const FoodAiException('Gemini 現在很忙，等一下再試一次。');
      // 預付點數歸零；整個帳戶底下的 key 都會停掉，重試沒用。
      case 402:
        throw const FoodAiException('Gemini 帳戶的點數用完了，要去 AI Studio 加值或換一把 key。');
      case 401:
      case 403:
        throw const FoodAiException('Gemini 不接受這把 API key，請確認設定裡的值。');
      default:
        throw FoodAiException('Gemini 回了錯誤（${response.statusCode}），請稍後再試。');
    }

    return _parse(utf8.decode(response.bodyBytes));
  }

  FoodNutrition _parse(String body) {
    const unreadable = FoodAiException('看不懂 Gemini 的回覆，請換個說法再試一次。');

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw unreadable;
    }
    if (decoded is! Map<String, dynamic>) throw unreadable;

    // steps 裡挑出 model_output，再從它的 content 取第一段文字。
    final steps = decoded['steps'];
    if (steps is! List) throw unreadable;
    String? text;
    for (final step in steps) {
      if (step is! Map || step['type'] != 'model_output') continue;
      final content = step['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          text = part['text'] as String;
          break;
        }
      }
      if (text != null) break;
    }
    if (text == null) throw unreadable;

    Object? payload;
    try {
      payload = jsonDecode(text);
    } on FormatException {
      throw unreadable;
    }
    if (payload is! Map<String, dynamic>) throw unreadable;

    final kcal = _number(payload['kcal']);
    if (kcal == null) throw unreadable;

    return FoodNutrition(
      kcal: kcal,
      proteinG: _number(payload['protein_g']),
      fatG: _number(payload['fat_g']),
    );
  }

  static double? _number(Object? v) => v is num ? v.toDouble() : null;
}
