import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';

/// 每日打勾（肌酸等），可記劑量。
class CheckRepository {
  CheckRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<Set<CheckItem>> watchDay(DateTime day) =>
      watchDayAmounts(day).map((m) => m.keys.toSet());

  /// [day] 打了哪些勾與劑量（舊紀錄沒有劑量時是 null）。
  Stream<Map<CheckItem, double?>> watchDayAmounts(DateTime day) {
    final t = _db.dailyChecks;
    return (_db.select(t)..where((r) => r.day.equals(dayKey(day)))).watch().map(
      (rows) => {for (final r in rows) r.item: r.amount},
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

  /// 最近一次記下的劑量；從沒記過時用 [CheckItem.defaultAmount]。
  Future<double> nextAmount(CheckItem item) async {
    final t = _db.dailyChecks;
    final last =
        await (_db.select(t)
              ..where((r) => r.item.equalsValue(item) & r.amount.isNotNull())
              ..orderBy([(r) => OrderingTerm.desc(r.day)])
              ..limit(1))
            .getSingleOrNull();
    return last?.amount ?? item.defaultAmount;
  }

  /// 打勾 / 取消。打勾沒給 [amount] 時沿用 [nextAmount]。
  Future<void> set(
    DateTime day,
    CheckItem item,
    bool checked, {
    double? amount,
  }) async {
    final t = _db.dailyChecks;
    if (checked) {
      final dose = amount ?? await nextAmount(item);
      await _db
          .into(t)
          .insertOnConflictUpdate(
            DailyChecksCompanion.insert(
              day: dayKey(day),
              item: item,
              checkedAt: _clock(),
              amount: Value(dose),
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
