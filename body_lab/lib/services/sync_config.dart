/// 同步伺服器的位址與金鑰，由編譯時的 `--dart-define` 帶入。
///
/// ```
/// flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:8000 \
///             --dart-define=SUPABASE_KEY=sb_publishable_...
/// ```
///
/// 不寫進程式碼也不進版控：自架的位址和金鑰是每個人自己的。
/// 沒帶這兩個值時 [configured] 是 false，整個同步功能關閉，
/// App 的行為跟加同步之前完全一樣。
///
/// CI 的 release 建置不會帶這兩個值，所以發出去的版本同步是關的——
/// 在 NAS 架好 HTTPS 之前本來就不該開（iOS 的 ATS 會擋掉明文 HTTP）。
class SyncConfig {
  const SyncConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;
}
