import '../data/database.dart';
import '../data/profile_repository.dart';
import 'tdee.dart';

/// 每日消耗的算法，依個人資料而定。
///
/// - 手錶模式：基礎代謝（Mifflin，存個人資料時的體重 / 年齡）+ 當天活動消耗；
///   當天沒有手錶資料時退回固定 TDEE。
/// - 固定模式：每天都是固定 TDEE。
class EnergyModel {
  EnergyModel(this.profile)
    : bmr = mifflinBmr(
        sex: profile.sex,
        weightKg: profile.weightKg,
        heightCm: profile.heightCm,
        age: profile.ageIn(profile.updatedAt.year),
      );

  final Profile profile;

  /// 基礎代謝（kcal / 天），固定不變。
  final double bmr;

  bool get usesWatch => profile.energyMode == EnergyMode.watch;

  /// 當天的總消耗。
  double expenditure(double? activeKcal) =>
      usesWatch && activeKcal != null ? bmr + activeKcal : profile.tdeeKcal;

  /// 這天的消耗是不是用手錶資料算的（否則是固定 TDEE）。
  bool fromWatch(double? activeKcal) => usesWatch && activeKcal != null;
}
