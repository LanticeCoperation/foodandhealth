import 'package:supabase/supabase.dart';

/// 同步要用到的伺服器操作。抽成介面是為了能用假的實作做單元測試，
/// 不必每次都連真的伺服器。
abstract class SyncApi {
  /// 目前登入者的 uid；沒登入是 null。
  String? get currentUserId;

  /// 以 syncId 為鍵的 upsert。重送同一批不會產生重複列。
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> rows);

  /// 拉回「自己的」飲食紀錄，依 updated_at、sync_id 排序，一次一頁。
  ///
  /// [since] 是上次的游標；呼叫端已經往回退過幾秒，這裡直接用。
  /// [offset] / [limit] 是分頁——伺服器的 PGRST_DB_MAX_ROWS 預設 1000，
  /// 不分頁的話第一次同步會被截斷，而被截掉的那些列的 updated_at
  /// 早於新游標，之後再也不會被抓到。
  Future<List<Map<String, dynamic>>> fetchFoodEntries({
    DateTime? since,
    int offset = 0,
    int limit = 500,
  });

  /// 把這些 syncId 標成已刪除（寫 deleted_at，不是真的刪）。
  Future<void> markDeleted(List<String> syncIds);
}

/// 伺服器被拒絕的操作，例如拿到別人的 syncId 想覆蓋。
class SyncRejected implements Exception {
  SyncRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseSyncApi implements SyncApi {
  SupabaseSyncApi(this._client);

  final SupabaseClient _client;

  static const _table = 'food_entries';

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  /// 一次送多少列。太大一包會卡在請求大小上限。
  static const int uploadChunk = 500;

  @override
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      for (var i = 0; i < rows.length; i += uploadChunk) {
        final end = (i + uploadChunk).clamp(0, rows.length);
        await _client
            .from(_table)
            .upsert(rows.sublist(i, end), onConflict: 'sync_id');
      }
    } on PostgrestException catch (e) {
      // 42501 = permission denied；RLS 擋下來的（例如備份來自別的帳號，
      // 裡面的 syncId 屬於別人）。重試幾次也不會變，直接往上拋。
      if (e.code == '42501' || e.code == '403') {
        throw SyncRejected('伺服器拒絕這批資料：${e.message}');
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFoodEntries({
    DateTime? since,
    int offset = 0,
    int limit = 500,
  }) async {
    final uid = currentUserId;
    var query = _client.from(_table).select();
    // 只拉自己的。家人的資料本來就不落地，拉回來只是白佔分頁的額度，
    // 還會把真正要的列擠出這一頁。
    if (uid != null) query = query.eq('user_id', uid);
    if (since != null) {
      query = query.gte('updated_at', since.toUtc().toIso8601String());
    }
    // 排序一定要穩定，分頁才不會漏列或重複
    final rows = await query
        .order('updated_at', ascending: true)
        .order('sync_id', ascending: true)
        .range(offset, offset + limit - 1);
    return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  }

  @override
  Future<void> markDeleted(List<String> syncIds) async {
    if (syncIds.isEmpty) return;
    await _client
        .from(_table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('sync_id', syncIds);
  }
}
