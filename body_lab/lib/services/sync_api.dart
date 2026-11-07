import 'package:supabase/supabase.dart';

/// 同步要用到的伺服器操作。抽成介面是為了能用假的實作做單元測試，
/// 不必每次都連真的伺服器。
abstract class SyncApi {
  /// 目前登入者的 uid；沒登入是 null。
  String? get currentUserId;

  /// 以 syncId 為鍵的 upsert。重送同一批不會產生重複列。
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> rows);

  /// 拉回自己與家人的飲食紀錄。
  ///
  /// [since] 是上次的游標；呼叫端已經往回退過幾秒，這裡直接用。
  Future<List<Map<String, dynamic>>> fetchFoodEntries({DateTime? since});

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

  @override
  Future<void> upsertFoodEntries(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      await _client.from(_table).upsert(rows, onConflict: 'sync_id');
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
  Future<List<Map<String, dynamic>>> fetchFoodEntries({DateTime? since}) async {
    var query = _client.from(_table).select();
    if (since != null) {
      query = query.gte('updated_at', since.toUtc().toIso8601String());
    }
    final rows = await query;
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
