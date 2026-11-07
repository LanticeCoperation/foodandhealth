import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database.dart';
import 'family_admin_api.dart';
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
    this.weightKg,
    this.bodyFatPercent,
  });

  final String userId;
  final String displayName;
  final bool isSelf;
  final double kcal;
  final double proteinG;
  final int entries;

  /// 這天的體重 / 體脂（來自 body_metrics，只上傳的健康快取）；沒量就是 null。
  final double? weightKg;
  final double? bodyFatPercent;
}

/// 把登入狀態與 [SyncService] 包成畫面好用的形狀。
///
/// 沒設定 [SyncConfig] 時 [available] 是 false，整個同步區塊不顯示。
class SyncController extends ChangeNotifier {
  /// [client] 不給時用 `Supabase.instance.client`——那是 main() 初始化過、
  /// 會把 session 存到裝置上的那一個。自己 new 一個 [SupabaseClient] 的話
  /// session 只活在記憶體裡，App 一關就要重新登入。
  SyncController(this._db, {SupabaseClient? client, SyncApi? api})
    : _client = client ?? SyncRuntime.client,
      _testApi = api {
    if (_testApi != null) {
      _service = SyncService(_db, _testApi);
      return;
    }
    if (_client != null) {
      _service = SyncService(_db, SupabaseSyncApi(_client));
      _authSub = _client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }

  final AppDatabase _db;
  final SupabaseClient? _client;

  /// 測試用的假伺服器；正式執行時是 null。
  final SyncApi? _testApi;
  SyncService? _service;
  StreamSubscription<AuthState>? _authSub;

  bool _busy = false;
  String? _lastMessage;
  DateTime? _lastSyncedAt;
  int _pending = 0;
  bool _offline = false;
  String? _ownerUid;

  bool get available => _client != null || _testApi != null;
  bool get busy => _busy;
  String? get lastMessage => _lastMessage;

  /// 上次同步成功的時間；從來沒成功過是 null。
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// 還有幾筆本機變更在排隊。
  int get pendingCount => _pending;

  /// 上次嘗試時連不到伺服器（多半是不在家裡的網路上）。
  bool get offline => _offline;

  /// 這支手機的資料綁在哪個帳號上；還沒登入過是 null。
  String? get ownerUid => _ownerUid;

  /// 家庭管理（建帳號、加成員）。沒設定伺服器時是 null。
  FamilyAdminApi? get familyAdmin =>
      _client == null ? null : FamilyAdminApi(_client);

  String? get _currentUserId =>
      _testApi != null ? _testApi.currentUserId : _client?.auth.currentUser?.id;

  /// 綁定的帳號跟現在登入的不是同一個——通常是換過伺服器。
  bool get ownerMismatch =>
      _ownerUid != null && signedIn && _ownerUid != _currentUserId;
  String? get email => _client?.auth.currentUser?.email;
  bool get signedIn =>
      _testApi != null
          ? _testApi.currentUserId != null
          : _client?.auth.currentUser != null;

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

  /// 自動同步：App 啟動與回到前景時各試一次。
  ///
  /// 伺服器在家裡的 NAS 上，所以人不在家時每次都會連不上——這是正常狀況，
  /// 不是錯誤。連不到就安靜地把變更留在本機排隊，回到家再送，
  /// 不要跳錯誤訊息打擾使用者。
  Future<void> autoSync() async {
    if (!signedIn || _busy) {
      await refreshStatus();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await _service!.sync();
      _offline = false;
      if (!result.idle) _lastMessage = result.toString();
    } on SyncRejected catch (e) {
      _lastMessage = e.message;
    } catch (e) {
      // 連線類的錯誤安靜處理，其他的才留訊息
      if (_looksOffline(e)) {
        _offline = true;
      } else {
        _lastMessage = '同步失敗：$e';
      }
    } finally {
      _busy = false;
      await refreshStatus();
    }
  }

  static bool _looksOffline(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    if (e is ClientException) return true;
    final text = e.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection timed out') ||
        text.contains('network is unreachable');
  }

  /// 解除這支手機的歸屬，讓它可以用別的帳號同步。見 [SyncService.resetOwner]。
  Future<void> resetOwner() async {
    await _service?.resetOwner();
    await refreshStatus();
  }

  /// 重新讀「上次同步時間」與「待上傳筆數」。
  Future<void> refreshStatus() async {
    final service = _service;
    if (service != null) {
      _lastSyncedAt = await service.lastSyncedAt();
      _pending = await service.pendingCount();
      _ownerUid = await service.ownerUid();
    }
    notifyListeners();
  }

  /// 家人（含自己）某一天的攝取概況。資料直接從伺服器讀，不落地。
  Future<List<FamilyDaySummary>> familyDay(DateTime day) async {
    final client = _client;
    if (client == null || !signedIn) return const [];
    final me = client.auth.currentUser!.id;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final db = client.schema(kBodyLabSchema);
    final profiles = await db.from('profiles').select('user_id,display_name');
    final rows = await db
        .from('food_entries')
        .select('user_id,kcal,protein_g,servings')
        .gte('eaten_at', start.toUtc().toIso8601String())
        .lt('eaten_at', end.toUtc().toIso8601String())
        .isFilter('deleted_at', null);
    final dayKey =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final metrics = await db
        .from('body_metrics')
        .select('user_id,weight_kg,body_fat_percent')
        .eq('day', dayKey)
        .isFilter('deleted_at', null);
    final weight = <String, double>{};
    final fat = <String, double>{};
    for (final m in metrics) {
      final uid = m['user_id'] as String;
      final w = (m['weight_kg'] as num?)?.toDouble();
      if (w != null) weight[uid] = w;
      final f = (m['body_fat_percent'] as num?)?.toDouble();
      if (f != null) fat[uid] = f;
    }

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
          weightKg: weight[entry.key],
          bodyFatPercent: fat[entry.key],
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
