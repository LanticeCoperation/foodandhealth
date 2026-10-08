import 'package:drift/drift.dart';

import 'database.dart';

/// 個人資料（只有一列）。
class ProfileRepository {
  ProfileRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static const _id = 1;

  Stream<Profile?> watch() => (_db.select(
    _db.profiles,
  )..where((r) => r.id.equals(_id))).watchSingleOrNull();

  Future<Profile?> get() => (_db.select(
    _db.profiles,
  )..where((r) => r.id.equals(_id))).getSingleOrNull();

  Future<void> save({
    required Sex sex,
    required int birthYear,
    required double heightCm,
    required ActivityLevel activity,
    required double weightKg,
    required double tdeeKcal,
  }) => _db
      .into(_db.profiles)
      .insertOnConflictUpdate(
        ProfilesCompanion.insert(
          id: const Value(_id),
          sex: sex,
          birthYear: birthYear,
          heightCm: heightCm,
          activity: activity,
          weightKg: weightKg,
          tdeeKcal: tdeeKcal,
          updatedAt: _clock(),
        ),
      );
}

extension ProfileAge on Profile {
  int ageIn(int year) => year - birthYear;
}
