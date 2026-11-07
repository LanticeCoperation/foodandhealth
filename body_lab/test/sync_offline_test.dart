import 'dart:io';

import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/food_repository.dart';
import 'package:body_lab/services/sync_api.dart';
import 'package:body_lab/services/sync_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 不在家裡的網路上：連不到伺服器。
class OfflineApi implements SyncApi {
  @override
  String? currentUserId = 'user-a';

  @override
  Future<void> upsert(
    String table,
    String onConflict,
    List<Map<String, dynamic>> rows,
  ) async {
    throw const SocketException('Connection refused');
  }

  @override
  Future<List<Map<String, dynamic>>> fetch(
    String table, {
    DateTime? since,
    int offset = 0,
    int limit = 500,
  }) async {
    throw const SocketException('Connection refused');
  }

  @override
  Future<void> markDeleted(
    String table,
    List<Map<String, String>> keys,
  ) async {
    throw const SocketException('Connection refused');
  }
}

void main() {
  late AppDatabase db;
  late FoodRepository repo;
  late SyncController controller;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FoodRepository(db);
    controller = SyncController(db, api: OfflineApi());
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test('連不到伺服器時：紀錄照常留在本機，排隊等著，不跳錯誤', () async {
    await repo.add(
      FoodEntriesCompanion.insert(
        eatenAt: DateTime(2026, 11, 7, 12),
        meal: MealType.lunch,
        name: '在外面吃的',
        kcal: const Value(600),
      ),
    );

    await controller.autoSync();

    // 資料還在
    final rows = await db.select(db.foodEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.pendingSync, isTrue, reason: '還沒送出去就要繼續排隊');

    // 使用者不該看到錯誤訊息，只要知道現在連不到
    expect(controller.offline, isTrue);
    expect(controller.lastMessage, isNull);
    expect(controller.pendingCount, 1);
    expect(controller.lastSyncedAt, isNull);
  });

  test('離線期間累積的變更會一直排著', () async {
    for (var i = 0; i < 3; i++) {
      await repo.add(
        FoodEntriesCompanion.insert(
          eatenAt: DateTime(2026, 11, 7, 8 + i),
          meal: MealType.lunch,
          name: 'M$i',
        ),
      );
      await controller.autoSync();
    }
    expect(controller.pendingCount, 3);
    expect(controller.offline, isTrue);
  });
}
