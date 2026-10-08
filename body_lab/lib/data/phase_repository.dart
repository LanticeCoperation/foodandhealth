import 'package:drift/drift.dart';

import '../utils/dates.dart';
import 'database.dart';

/// 預設一個階段 4 週。
const int kDefaultPhaseDays = 28;

extension PhaseDates on Phase {
  DateTime get start => parseDayKey(startDay);
  DateTime get end => parseDayKey(endDay);
  int get lengthDays => end.difference(start).inDays + 1;
  bool contains(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

class PhaseOverlapException implements Exception {
  PhaseOverlapException(this.other);
  final Phase other;

  @override
  String toString() => '和「${other.name}」的日期重疊';
}

class PhaseRepository {
  PhaseRepository(this._db);

  final AppDatabase _db;

  /// 新的在前。
  Stream<List<Phase>> watchAll() => _allQuery().watch();

  Future<List<Phase>> all() => _allQuery().get();

  SimpleSelectStatement<$PhasesTable, Phase> _allQuery() =>
      _db.select(_db.phases)..orderBy([(r) => OrderingTerm.desc(r.startDay)]);

  /// [day] 所在的階段（沒有則 null）。
  Stream<Phase?> watchOn(DateTime day) {
    final key = dayKey(day);
    return (_db.select(_db.phases)..where(
          (r) =>
              r.startDay.isSmallerOrEqualValue(key) &
              r.endDay.isBiggerOrEqualValue(key),
        ))
        .watchSingleOrNull();
  }

  /// 新增或修改（[id] 有值時）。日期和其他階段重疊時丟 [PhaseOverlapException]。
  Future<int> save(PhasesCompanion phase, {int? id}) {
    return _db.transaction(() async {
      final overlap = await _findOverlap(
        phase.startDay.value,
        phase.endDay.value,
        excludeId: id,
      );
      if (overlap != null) throw PhaseOverlapException(overlap);
      if (id == null) return _db.into(_db.phases).insert(phase);
      await (_db.update(
        _db.phases,
      )..where((r) => r.id.equals(id))).write(phase);
      return id;
    });
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.phases)..where((r) => r.id.equals(id))).go();

  Future<Phase?> _findOverlap(
    String start,
    String end, {
    int? excludeId,
  }) async {
    final query = _db.select(_db.phases)
      ..where((r) {
        final overlaps =
            r.startDay.isSmallerOrEqualValue(end) &
            r.endDay.isBiggerOrEqualValue(start);
        return excludeId == null
            ? overlaps
            : overlaps & r.id.equals(excludeId).not();
      })
      ..limit(1);
    return query.getSingleOrNull();
  }
}
