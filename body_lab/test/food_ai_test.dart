import 'dart:convert';
import 'dart:io';

import 'package:body_lab/services/food_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// Interactions API 成功時的回覆：model_output 裡那段文字就是我們要的 JSON。
  String reply(String jsonText) => jsonEncode({
    'id': 'v1_test',
    'status': 'completed',
    'object': 'interaction',
    'model': kGeminiModel,
    'steps': [
      {'type': 'thought', 'signature': 'xxx'},
      {
        'type': 'model_output',
        'content': [
          {'type': 'text', 'text': jsonText},
        ],
      },
    ],
  });

  FoodAi ai(
    Future<http.Response> Function(http.Request) handler, {
    String apiKey = 'test-key',
  }) => FoodAi(client: MockClient(handler), apiKey: apiKey);

  /// http.Response 的字串建構子是 Latin-1，中文要走 bytes。
  http.Response utf8Response(String body, int status) =>
      http.Response.bytes(utf8.encode(body), status);

  FoodAi ok(String jsonText, {void Function(http.Request)? capture}) => ai((
    req,
  ) async {
    capture?.call(req);
    return utf8Response(reply(jsonText), 200);
  });

  test('解析熱量、蛋白質、脂肪', () async {
    final n = await ok(
      '{"kcal": 620, "protein_g": 18.5, "fat_g": 22}',
    ).lookup('一碗滷肉飯');

    expect(n.kcal, 620);
    expect(n.proteinG, 18.5);
    expect(n.fatG, 22);
  });

  test('真實回應（實際打過 API 拿回來的）解得出來', () async {
    // fixtures/gemini_interaction.json 是 2026-11-05 對 gemini-3.5-flash-lite
    // 實際打一次拿回來的回應原文，只縮短了 id 與 signature。
    final body = File(
      'test/fixtures/gemini_interaction.json',
    ).readAsStringSync();
    final service = ai(
      (_) async => http.Response.bytes(utf8.encode(body), 200),
    );

    final n = await service.lookup('一碗滷肉飯');

    expect(n.kcal, 550);
    expect(n.proteinG, 12);
    expect(n.fatG, 20);
  });

  test('蛋白質、脂肪可以缺少', () async {
    final n = await ok('{"kcal": 90}').lookup('一顆蘋果');

    expect(n.kcal, 90);
    expect(n.proteinG, isNull);
    expect(n.fatG, isNull);
  });

  test('送出的請求帶著模型、描述與 JSON schema', () async {
    late http.Request sent;
    await ok(
      '{"kcal": 100}',
      capture: (r) => sent = r,
    ).lookup('雞腿便當');

    expect(sent.method, 'POST');
    expect(sent.url.toString(), kGeminiEndpoint);
    expect(sent.headers['x-goog-api-key'], 'test-key');
    expect(sent.headers['Api-Revision'], kGeminiApiRevision);

    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], kGeminiModel);
    expect(body['input'], contains('雞腿便當'));

    final schema =
        (body['response_format'] as Map)['schema'] as Map<String, dynamic>;
    expect((body['response_format'] as Map)['mime_type'], 'application/json');
    expect((schema['properties'] as Map).keys, containsAll(['kcal', 'protein_g', 'fat_g']));
    expect(schema['required'], contains('kcal'));
  });

  test('沒設 API key：直接說要去設定，不發請求', () async {
    var called = false;
    final service = ai((_) async {
      called = true;
      return http.Response(reply('{"kcal": 1}'), 200);
    }, apiKey: '   ');

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('描述留空：不發請求', () async {
    var called = false;
    final service = ai((_) async {
      called = true;
      return http.Response(reply('{"kcal": 1}'), 200);
    });

    await expectLater(service.lookup('  '), throwsA(isA<FoodAiException>()));
    expect(called, isFalse);
  });

  test('429：提示免費額度用完', () async {
    final service = ai((_) async => http.Response('quota', 429));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('額度'),
        ),
      ),
    );
  });

  test('402：提示帳戶點數用完，不是網路問題', () async {
    final service = ai((_) async => http.Response('depleted', 402));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('點數'),
        ),
      ),
    );
  });

  test('401/403：提示 key 可能無效', () async {
    final service = ai((_) async => http.Response('denied', 403));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  test('其他 HTTP 錯誤：帶上狀態碼', () async {
    final service = ai((_) async => http.Response('boom', 500));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('連不上：提示檢查網路', () async {
    final service = ai((_) async => throw const SocketException('no route'));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('網路'),
        ),
      ),
    );
  });

  test('回覆不是 JSON：提示看不懂', () async {
    final service = ai((_) async => utf8Response(reply('我不知道耶'), 200));

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(
        isA<FoodAiException>().having(
          (e) => e.message,
          'message',
          contains('看不懂'),
        ),
      ),
    );
  });

  test('回覆缺少熱量：提示看不懂', () async {
    final service = ok('{"protein_g": 10}');

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(isA<FoodAiException>()),
    );
  });

  test('整包回覆少了 model_output：提示看不懂', () async {
    final service = ai(
      (_) async => http.Response(
        jsonEncode({
          'status': 'completed',
          'steps': [
            {'type': 'thought', 'signature': 'xxx'},
          ],
        }),
        200,
      ),
    );

    await expectLater(
      service.lookup('一碗飯'),
      throwsA(isA<FoodAiException>()),
    );
  });
}
