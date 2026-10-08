import 'package:body_lab/analysis/combo_heatmap.dart';
import 'package:body_lab/analysis/tdee.dart';
import 'package:body_lab/data/database.dart';
import 'package:body_lab/data/profile_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

WeekSample week(double? balance) => WeekSample(
  start: DateTime(2026, 1, 1),
  end: DateTime(2026, 1, 7),
  foodDays: 7,
  creatineDays: 0,
  kcal: balance == null ? null : 2300 + balance,
  balance: balance,
);

void main() {
  test('Mifflin-St Jeor 基礎代謝', () {
    // 男 30 歲 180 cm 80 kg：800 + 1125 − 150 + 5 = 1780
    expect(
      mifflinBmr(sex: Sex.male, weightKg: 80, heightCm: 180, age: 30),
      1780,
    );
    // 女 30 歲 165 cm 60 kg：600 + 1031.25 − 150 − 161 = 1320.25
    expect(
      mifflinBmr(sex: Sex.female, weightKg: 60, heightCm: 165, age: 30),
      closeTo(1320.25, 1e-9),
    );
  });

  test('TDEE = 基礎代謝 × 活動量，取整到 10', () {
    // 1780 × 1.55 = 2759 → 2760
    expect(
      estimateTdee(
        sex: Sex.male,
        weightKg: 80,
        heightCm: 180,
        age: 30,
        activity: ActivityLevel.moderate,
      ),
      2760,
    );
  });

  test('赤字 / 盈餘文字', () {
    expect(formatBalance(-512.4), '赤字 512 kcal');
    expect(formatBalance(130), '盈餘 130 kcal');
    expect(formatBalance(0.3), '持平');
  });

  test('個人資料只有一列，再存一次是覆蓋', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ProfileRepository(db, clock: () => DateTime(2026, 10, 8));
    expect(await repo.get(), isNull);

    Future<void> save(double tdee) => repo.save(
      sex: Sex.female,
      birthYear: 1990,
      heightCm: 165,
      activity: ActivityLevel.light,
      weightKg: 60,
      tdeeKcal: tdee,
    );
    await save(1800);
    await save(1850);

    final p = (await repo.get())!;
    expect(p.tdeeKcal, 1850);
    expect(p.ageIn(2026), 36);
    expect(await db.select(db.profiles).get(), hasLength(1));
    await db.close();
  });

  test('有每日消耗時熱量依平均每日赤字分組', () {
    final b = bucketsFor(HeatmapFactor.kcal, [week(-600)]);
    expect(b.labels, ['赤字 >500', '赤字 0–500', '盈餘']);
    expect(b.classify(week(-600)), 0);
    expect(b.classify(week(-300)), 1);
    expect(b.classify(week(0)), 2); // 持平算盈餘那組
    expect(b.classify(week(null)), isNull);
  });
}
