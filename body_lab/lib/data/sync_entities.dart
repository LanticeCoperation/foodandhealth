import 'database.dart';

/// [PendingDeletes.entity] 的值：哪一張表的刪除待辦。
const kEntityFoodEntries = 'food_entries';
const kEntityDailyChecks = 'daily_checks';
const kEntityPhases = 'phases';
const kEntityExtraBurns = 'extra_burns';

/// 自然鍵的表沒有 syncId，用 "day|item" 當待辦的鍵。
///
/// 形狀跟 UUID 不同，所以和其他表的鍵放在同一張待辦表裡也不會相撞。
String checkKey(String day, CheckItem item) => '$day|${item.name}';
