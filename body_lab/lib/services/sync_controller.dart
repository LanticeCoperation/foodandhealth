import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../data/database.dart';
import 'sync_api.dart';
import 'sync_config.dart';
import 'sync_service.dart';

/// 家人（含自己）某一天的攝取概況。
class FamilyDaySummary {
  const FamilyDaySummary({
    required this.userId,
    required this.displayName,
    required this.isSelf,
    required this.kcal,
    required this.proteinG,
    required this.entries,
  });

  final String userId;
  final String displayName;
  final bool isSelf;
  final double kcal;
  final double proteinG;
  final int entries;
}

/// 把登入狀態與 [SyncService] 包成畫面好用的形狀。
///
/// 沒設定 [SyncConfig] 時 [available] 是 false，整個同步區塊不顯示。
class SyncController extends ChangeNotifier {
  SyncController(this._db, {SupabaseClient? client})
    : _client =
          client ??
          (SyncConfig.configured
              ? SupabaseClient(SyncConfig.url, SyncConfig.publishableKey)
              : null) {
    if (_client != null) {
      _service = SyncService(_db, SupabaseSyncApi(_client));
      _authSub = _client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }

  final AppDatabase _db;
  final SupabaseClient? _client;
  SyncService? _service;
  StreamSubscription<AuthState>? _authSub;

  bool _busy = false;
  String? _lastMessage;

  bool get available => _client != null;
  bool get busy => _busy;
  String? get lastMessage => _lastMessage;
  String? get email => _client?.auth.currentUser?.email;
  bool get signedIn => _client?.auth.currentUser != null;

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> signIn(String email, String password) async {
    final client = _client;
    if (client == null) throw StateError('沒有設定同步伺服器');
    await _run(() async {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      // 認領這台的既有資料。帳號不對就在這裡擋下來，不要讓資料上傳。
      await _service!.claimForCurrentUser();
      final result = await _service!.sync();
      _lastMessage = result.idle ? '已是最新' : result.toString();
    });
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
    _lastMessage = null;
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!signedIn) return;
    await _run(() async {
      final result = await _service!.sync();
      _lastMessage = result.idle ? '已是最新' : result.toString();
    });
  }

  /// 這台認領的帳號 uid；還沒登入過是 null。
  Future<String?> ownerUid() async => _service?.ownerUid();

  /// 家人（含自己）某一天的攝取概況。資料直接從伺服器讀，不落地。
  Future<List<FamilyDaySummary>> familyDay(DateTime day) async {
    final client = _client;
    if (client == null || !signedIn) return const [];
    final me = client.auth.currentUser!.id;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final profiles = await client.from('profiles').select('user_id,display_name');
    final rows = await client
        .from('food_entries')
        .select('user_id,kcal,protein_g,servings')
        .gte('eaten_at', start.toUtc().toIso8601String())
        .lt('eaten_at', end.toUtc().toIso8601String())
        .isFilter('deleted_at', null);

    final names = <String, String>{
      for (final p in profiles)
        p['user_id'] as String: p['display_name'] as String,
    };
    final kcal = <String, double>{};
    final protein = <String, double>{};
    final count = <String, int>{};
    for (final r in rows) {
      final uid = r['user_id'] as String;
      final servings = (r['servings'] as num?)?.toDouble() ?? 1;
      kcal[uid] = (kcal[uid] ?? 0) + ((r['kcal'] as num?)?.toDouble() ?? 0) * servings;
      protein[uid] =
          (protein[uid] ?? 0) + ((r['protein_g'] as num?)?.toDouble() ?? 0) * servings;
      count[uid] = (count[uid] ?? 0) + 1;
    }

    final summaries = [
      for (final entry in names.entries)
        FamilyDaySummary(
          userId: entry.key,
          displayName: entry.value,
          isSelf: entry.key == me,
          kcal: kcal[entry.key] ?? 0,
          proteinG: protein[entry.key] ?? 0,
          entries: count[entry.key] ?? 0,
        ),
    ];
    // 自己排最前面，其他依名稱
    summaries.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return summaries;
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _lastMessage = null;
    notifyListeners();
    try {
      await action();
    } on WrongOwnerException catch (e) {
      _lastMessage = e.toString();
    } on AuthException catch (e) {
      _lastMessage = '登入失敗：${e.message}';
    } on SyncRejected catch (e) {
      _lastMessage = e.message;
    } catch (e) {
      _lastMessage = '同步失敗：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
