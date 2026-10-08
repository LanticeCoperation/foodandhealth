# Body Lab — 第一步：讀取身體組成

目標：從 Apple 健康（iOS）/ Health Connect（Android）讀取
**體重、體脂%、除脂體重**，每天只取最早一筆（起床測量），
並計算脂肪重量與 7 日移動平均。

## 1. 專案（已建立）

專案在 `body_lab/`（`flutter create --org com.yourname --platforms ios,android body_lab`），
已加入 `health` 套件，平台設定都已套用。上架前記得把 `com.yourname` 換成自己的
（Android `applicationId`/`namespace`/MainActivity package、iOS Bundle Identifier）。

```bash
cd body_lab
flutter pub get
flutter test
```

## 2. iOS 設定

已完成：
- `ios/Runner/Info.plist` 加入 `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`
- `ios/Runner/Runner.entitlements` 開啟 HealthKit，並設定 `CODE_SIGN_ENTITLEMENTS`
- 部署目標 iOS 15.0

需要在 Mac 上手動做：
1. `open ios/Runner.xcworkspace` → Runner target → Signing & Capabilities →
   選你的 Team，確認 **HealthKit** 出現在 capability 列表（沒出現就 `+ Capability` 加一次）
2. 只能用**實機**測試，模擬器沒有你的健康資料

## 3. Android 設定（Health Connect）

已完成：
- `android/app/build.gradle.kts`：`minSdk = 26`
- `AndroidManifest.xml`：讀取體重 / 體脂 / 除脂體重 / 歷史資料權限、
  權限說明 intent-filter、`ViewPermissionUsageActivity`、Health Connect `<queries>`
- `MainActivity` 改成 `FlutterFragmentActivity`
- `android/gradle.properties`：`kotlin.incremental=false`（Windows 上專案與 pub cache
  在不同磁碟時 Kotlin 增量編譯會失敗）

Android 14 以上 Health Connect 內建在系統；Android 13 以下要從 Play 商店安裝
（App 偵測到沒安裝會顯示安裝按鈕）。Health Connect 預設只給授權後 30 天的資料，
App 會另外要求「讀取歷史資料」權限以取得 90 天。

## 4. 執行

```bash
flutter run
```

第一次開啟會跳出權限畫面，把體重、體脂、除脂體重都打開。
列表會顯示每天的數值、7 日平均，偏離平均超過 0.8 kg 的天會標記水滴圖示。
除脂體重後面有「*推算」表示體脂計沒寫入，由 體重 × (1 − 體脂%) 算出。

## 專案結構

```
body_lab/
  lib/
    main.dart                     建立資料庫與服務、底部頁籤（身體 / 飲食）
    models/body_metric.dart       每日身體組成資料
    services/health_service.dart  HealthKit / Health Connect 讀取、每日取第一筆
    data/database.dart            drift schema：健康資料快取、飲食紀錄
    data/body_repository.dart     快取讀取、從健康資料同步
    data/food_repository.dart     飲食紀錄 CRUD、每日總量
    utils/trend.dart              7 日移動平均、異常值判斷
    utils/dates.dart              當地日期、yyyy-MM-dd 日期鍵
    screens/body_screen.dart      身體組成列表（先顯示快取再同步）
    screens/food_screen.dart      單日飲食列表與總量
    screens/food_entry_sheet.dart 新增 / 編輯飲食
  test/                           單元測試 + 飲食頁 widget 測試
```

## 本地資料庫（drift）

- 資料庫檔案：App 文件目錄下的 `body_lab.sqlite`
- **健康資料快取** `daily_body_metrics`：每天一列。第一次同步抓 90 天，之後從快取最後一天
  往前 14 天重抓，並以重抓結果取代這段範圍（健康 App 裡刪掉的天也會消失）。
  讀到空資料時不動快取：iOS 被拒絕讀取時 HealthKit 只回傳空資料，和沒資料分不出來。
- **飲食紀錄** `food_entries`：時間、餐別、名稱、份量倍率，以及每份的熱量 / 蛋白質 /
  碳水 / 脂肪（都可留空），實際攝取 = 每份 × 份量。
- 改了 `lib/data/database.dart` 之後要重新產生程式碼，並把 `schemaVersion` +1、
  在 `migration` 加 `onUpgrade`：

```bash
dart run build_runner build
```

## 接下來

- [x] 本地資料庫（drift）：快取健康資料 + 存飲食紀錄
- [ ] 外食快速輸入：餐點範本、份量倍率、蛋白粉一鍵 +1、肌酸打勾
- [ ] 疊加趨勢圖（fl_chart）
- [ ] 階段（4 週實驗）功能
- [ ] 組合分析熱力圖
