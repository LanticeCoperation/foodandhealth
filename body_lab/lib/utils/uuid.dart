import 'dart:math';

final _random = Random.secure();

/// 產生 RFC 4122 第 4 版（隨機）UUID 的字串形式。
///
/// 同步用的 `syncId` 要由裝置自己產，而且必須全域唯一——
/// 本機的 autoIncrement id 在兩支手機上必定相撞。
/// 只需要這一個函式，不值得為此多一個套件相依。
String newUuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  // 版本（第 7 位元組高 4 bits = 0100）與變體（第 9 位元組高 2 bits = 10）
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}
