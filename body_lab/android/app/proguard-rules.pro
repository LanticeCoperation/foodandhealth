# Room 用反射呼叫 *_Impl 的無參數建構子建立資料庫；R8 會把它移除，
# 導致 WorkManager（廣告 SDK 依賴）在啟動時 crash：
# "Failed to create an instance of androidx.work.impl.WorkDatabase"
-keep class * extends androidx.room.RoomDatabase { <init>(); }
