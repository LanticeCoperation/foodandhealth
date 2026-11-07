import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// 同步伺服器的位址與金鑰。
///
/// **正常情況由使用者在設定頁填**，存在本機的 Settings 表裡。刻意不內嵌進 App：
/// 位址一旦編進 .ipa / .apk，任何人解壓縮就看得到伺服器在哪。放在設定裡的話，
/// 發出去的檔案不含任何關於位置的資訊，換伺服器也不用重發版。
///
/// `--dart-define` 只留給開發與自動化測試用：
///
/// ```
/// flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:8000 \
///             --dart-define=SUPABASE_KEY=sb_publishable_...
/// ```
///
/// 設定頁填的值優先，沒填才用編譯時帶進來的。
class SyncConfig {
  const SyncConfig._();

  /// 編譯時帶進來的預設值；release 建置不帶，所以是空字串。
  static const String compiledUrl = String.fromEnvironment('SUPABASE_URL');
  static const String compiledKey = String.fromEnvironment('SUPABASE_KEY');
}

/// main() 初始化好的 Supabase 連線。
///
/// `Supabase.initialize` 是全域的一次性動作，而位址要先從資料庫讀出來才知道，
/// 所以初始化在 main() 做完之後把 client 放在這裡給 [SyncController] 用。
/// 沒設定伺服器時是 null，同步功能整個關閉。
///
/// 使用者改了位址之後要重新啟動 App 才會生效——Supabase 不能重複初始化。
class SyncRuntime {
  const SyncRuntime._();

  static SupabaseClient? client;

  /// 這次啟動實際用的位址，拿來顯示給使用者看；沒設定是 null。
  static String? url;

  static bool get configured => client != null;
}
