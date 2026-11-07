import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// 家庭管理畫面用的伺服器端函式。
///
/// 建帳號需要 service_role 金鑰，那把金鑰**不在 App 裡**（放進來的話，
/// 任何人解壓縮 .ipa / .apk 就能繞過所有 RLS 讀寫整個資料庫）。
/// 金鑰留在伺服器端的 edge function，App 只把使用者輸入的管理密碼送過去驗。
///
/// 管理密碼不存在 App 裡，每次操作當場輸入。
class FamilyAdminApi {
  FamilyAdminApi(this._client);

  final SupabaseClient _client;

  static const _function = 'family-admin';

  Future<FamilyAdminResult> _call(
    String secret,
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    try {
      final res = await _client.functions.invoke(
        _function,
        body: {'secret': secret, 'action': action, ...extra},
      );
      final data = res.data;
      if (data is Map) {
        final err = data['error'];
        if (err != null) return FamilyAdminResult.failure('$err');
        return FamilyAdminResult.success(
          '${data['text'] ?? ''}',
          password: data['password'] as String?,
        );
      }
      return FamilyAdminResult.failure('伺服器回了看不懂的內容');
    } on FunctionException catch (e) {
      // 函式自己回的錯誤（密碼不對、email 重複…）會在這裡。
      // details 不一定是已經解析好的 Map，也可能是原始字串。
      final details = e.details;
      if (details is Map && details['error'] != null) {
        return FamilyAdminResult.failure('${details['error']}');
      }
      if (details is String && details.isNotEmpty) {
        try {
          final parsed = jsonDecode(details);
          if (parsed is Map && parsed['error'] != null) {
            return FamilyAdminResult.failure('${parsed['error']}');
          }
        } catch (_) {
          // 不是 JSON 就原樣顯示
        }
        return FamilyAdminResult.failure(details);
      }
      return FamilyAdminResult.failure('呼叫失敗（${e.status}）');
    } catch (e) {
      return FamilyAdminResult.failure('連不到伺服器：$e');
    }
  }

  Future<FamilyAdminResult> list(String secret) => _call(secret, 'list');

  Future<FamilyAdminResult> createFamily(String secret, String name) =>
      _call(secret, 'create-family', {'name': name});

  /// 建帳號並（有給 [family] 時）直接加進家庭。密碼留空由伺服器產生。
  Future<FamilyAdminResult> createMember(
    String secret, {
    required String email,
    required String name,
    String? family,
    String? password,
  }) => _call(secret, 'create-member', {
    'email': email,
    'name': name,
    if (family != null && family.isNotEmpty) 'family': family,
    if (password != null && password.isNotEmpty) 'password': password,
  });

  Future<FamilyAdminResult> addMember(
    String secret, {
    required String family,
    required String email,
    String role = 'member',
  }) => _call(secret, 'add-member', {
    'family': family,
    'email': email,
    'role': role,
  });

  Future<FamilyAdminResult> removeMember(
    String secret, {
    required String family,
    required String email,
  }) => _call(secret, 'remove-member', {'family': family, 'email': email});

  Future<FamilyAdminResult> setPassword(
    String secret, {
    required String email,
    String? password,
  }) => _call(secret, 'set-password', {
    'email': email,
    if (password != null && password.isNotEmpty) 'password': password,
  });
}

class FamilyAdminResult {
  const FamilyAdminResult.success(this.text, {this.password}) : error = null;
  const FamilyAdminResult.failure(this.error) : text = '', password = null;

  final String text;
  final String? error;

  /// 伺服器自動產生的密碼，只會回這一次。
  final String? password;

  bool get ok => error == null;
}
