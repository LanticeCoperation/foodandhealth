import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';
import 'sync_entities.dart';

/// 自訂消耗：手錶沒記錄到的活動，自己輸入熱量。
class ExtraBurnRepository {
  ExtraBurnRepository(this._db);

  final AppDatabase _db;

  Stream<List<ExtraBurn>> watchDay(DateTime day) {
    final t = _db.extraBurns;
    return (_db.select(t)
          ..where((r) => r.day.equals(dayKey(day)))
          ..orderBy([(r) => OrderingTerm.asc(r.id)]))
        .watch();
  }

  /// [from] 之後每天的自訂消耗總和，key 是當地日期 00:00。
  Future<Map<DateTime, double>> since(DateTime from) async {
    final t = _db.extraBurns;
    final rows = await (_db.select(
      t,
    )..where((r) => r.day.isBiggerOrEqualValue(dayKey(from)))).get();
    final result = <DateTime, double>{};
    for (final r in rows) {
      final day = parseDayKey(r.day);
      result[day] = (result[day] ?? 0) + r.kcal;
    }
    return result;
  }

  Future<int> add(DateTime day, double kcal, {String? note}) => _db
      .into(_db.extraBurns)
      .insert(
        ExtraBurnsCompanion.insert(
          day: dayKey(day),
          kcal: kcal,
          note: Value(note),
        ),
      );

  Future<void> update(int id, double kcal, {String? note}) =>
      (_db.update(_db.extraBurns)..where((r) => r.id.equals(id))).write(
        ExtraBurnsCompanion(kcal: Value(kcal), note: Value(note)),
      );

  /// 本機硬刪除，另外在待辦表記下 syncId（理由見 [PendingDeletes]）。
  Future<void> delete(int id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.extraBurns,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    final syncId = row?.syncId;
    if (syncId != null) {
      await _db
          .into(_db.pendingDeletes)
          .insertOnConflictUpdate(
            PendingDeletesCompanion.insert(
              entity: const Value(kEntityExtraBurns),
              syncId: syncId,
            ),
          );
    }
    await (_db.delete(_db.extraBurns)..where((r) => r.id.equals(id))).go();
  });

  /// 復原刪除：用原本的 id 放回去。
  /// 復原刪除：放回去、取消待辦，並重新標成待上傳
  /// （刪除可能已經送出去了，伺服器上有墓碑要救回來）。
  Future<void> restore(ExtraBurn burn) => _db.transaction(() async {
    await _db.into(_db.extraBurns).insert(burn.copyWith(pendingSync: true));
    final syncId = burn.syncId;
    if (syncId != null) {
      await (_db.delete(_db.pendingDeletes)..where(
            (r) =>
                r.entity.equals(kEntityExtraBurns) & r.syncId.equals(syncId),
          ))
          .go();
    }
  });
}
