import 'package:supabase/supabase.dart';

/// 同步要用到的伺服器操作。抽成介面是為了能用假的實作做單元測試，
/// 不必每次都連真的伺服器。
abstract class SyncApi {
  /// 目前登入者的 uid；沒登入是 null。
  String? get currentUserId;

  /// upsert。[onConflict] 是衝突鍵，重送同一批不會產生重複列。
  Future<void> upsert(
    String table,
    String onConflict,
    List<Map<String, dynamic>> rows,
  );

  /// 拉回「自己的」資料，依 updated_at 排序，一次一頁。
  ///
  /// [since] 是上次的游標；呼叫端已經往回退過幾秒，這裡直接用。
  /// [offset] / [limit] 是分頁——伺服器的 PGRST_DB_MAX_ROWS 預設 1000，
  /// 不分頁的話第一次同步會被截斷，而被截掉的那些列的 updated_at
  /// 早於新游標，之後再也不會被抓到。
  Future<List<Map<String, dynamic>>> fetch(
    String table, {
    DateTime? since,
    int offset = 0,
    int limit = 500,
  });

  /// 把符合條件的列標成已刪除（寫 deleted_at，不是真的刪）。
  ///
  /// [keys] 每一筆是一組等值條件，例如 `{'sync_id': '…'}` 或
  /// `{'day': '2026-11-07', 'item': 'creatine'}`。
  Future<void> markDeleted(String table, List<Map<String, String>> keys);
}

/// 伺服器拒絕的操作，例如拿到別人的 syncId 想覆蓋。
class SyncRejected implements Exception {
  SyncRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseSyncApi implements SyncApi {
  SupabaseSyncApi(this._client);

  final SupabaseClient _client;

  /// 一次送多少列。太大一包會卡在請求大小上限。
  static const int uploadChunk = 500;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> upsert(
    String table,
    String onConflict,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    try {
      for (var i = 0; i < rows.length; i += uploadChunk) {
        final end = (i + uploadChunk).clamp(0, rows.length);
        await _client
            .from(table)
            .upsert(rows.sublist(i, end), onConflict: onConflict);
      }
    } on PostgrestException catch (e) {
      // 42501 = permission denied；RLS 擋下來的（例如備份來自別的帳號，
      // 裡面的 syncId 屬於別人）。重試幾次也不會變，直接往上拋。
      if (e.code == '42501' || e.code == '403') {
        throw SyncRejected('伺服器拒絕 $table 的這批資料：${e.message}');
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetch(
    String table, {
    DateTime? since,
    int offset = 0,
    int limit = 500,
  }) async {
    final uid = currentUserId;
    var query = _client.from(table).select();
    // 只拉自己的。家人的資料本來就不落地，拉回來只是白佔分頁的額度，
    // 還會把真正要的列擠出這一頁。
    if (uid != null) query = query.eq('user_id', uid);
    if (since != null) {
      query = query.gte('updated_at', since.toUtc().toIso8601String());
    }
    // 排序要穩定，分頁才不會漏列或重複
    final rows = await query
        .order('updated_at', ascending: true)
        .range(offset, offset + limit - 1);
    return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  }

  @override
  Future<void> markDeleted(
    String table,
    List<Map<String, String>> keys,
  ) async {
    if (keys.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final key in keys) {
      var q = _client.from(table).update({'deleted_at': now});
      for (final entry in key.entries) {
        q = q.eq(entry.key, entry.value);
      }
      await q;
    }
  }
}
