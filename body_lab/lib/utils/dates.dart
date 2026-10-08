/// 當地日期的 00:00。
DateTime dateOnly(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 往前 / 往後 [days] 個日曆天（用年月日計算，不受日光節約影響）。
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// 資料庫用的日期鍵：yyyy-MM-dd。字串比較順序等於日期順序。
String dayKey(DateTime day) {
  final d = dateOnly(day);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

DateTime parseDayKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
