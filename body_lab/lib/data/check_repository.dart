import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';

/// 每日打勾（肌酸等）。
class CheckRepository {
  CheckRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<Set<CheckItem>> watchDay(DateTime day) {
    final t = _db.dailyChecks;
    return (_db.select(t)..where((r) => r.day.equals(dayKey(day)))).watch().map(
      (rows) => rows.map((r) => r.item).toSet(),
    );
  }

  /// [from] 之後每天打了哪些勾，key 是當地日期 00:00。
  Future<Map<DateTime, Set<CheckItem>>> since(DateTime from) async {
    final t = _db.dailyChecks;
    final rows = await (_db.select(
      t,
    )..where((r) => r.day.isBiggerOrEqualValue(dayKey(from)))).get();
    final result = <DateTime, Set<CheckItem>>{};
    for (final r in rows) {
      result.putIfAbsent(parseDayKey(r.day), () => {}).add(r.item);
    }
    return result;
  }

  Future<void> set(DateTime day, CheckItem item, bool checked) async {
    final t = _db.dailyChecks;
    if (checked) {
      await _db
          .into(t)
          .insertOnConflictUpdate(
            DailyChecksCompanion.insert(
              day: dayKey(day),
              item: item,
              checkedAt: _clock(),
            ),
          );
    } else {
      await (_db.delete(
            t,
          )..where((r) => r.day.equals(dayKey(day)) & r.item.equalsValue(item)))
          .go();
    }
  }
}
