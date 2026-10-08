import '../data/database.dart';

/// Mifflin-St Jeor 基礎代謝（kcal / 天）。
double mifflinBmr({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) => 10 * weightKg + 6.25 * heightCm - 5 * age + (sex == Sex.male ? 5 : -161);

/// TDEE = 基礎代謝 × 活動量係數，取整到 10 kcal。
double estimateTdee({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
  required ActivityLevel activity,
}) {
  final bmr = mifflinBmr(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
  );
  return (bmr * activity.factor / 10).roundToDouble() * 10;
}

/// 攝取 − TDEE：負數是赤字、正數是盈餘。
String formatBalance(double balance) {
  final v = balance.round();
  if (v == 0) return '持平';
  return v < 0 ? '赤字 ${-v} kcal' : '盈餘 $v kcal';
}
