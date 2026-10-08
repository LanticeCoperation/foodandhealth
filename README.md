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
    main.dart                     建立資料庫與服務、底部頁籤
    models/body_metric.dart       每日身體組成資料
    services/health_service.dart  HealthKit / Health Connect 讀取、每日取第一筆
    data/database.dart            drift schema：健康資料快取、飲食紀錄
    data/body_repository.dart     快取讀取、從健康資料同步
    data/food_repository.dart     飲食紀錄 CRUD、每日總量
    data/template_repository.dart 餐點範本、從範本加入
    data/check_repository.dart    每日打勾（肌酸）
    data/phase_repository.dart    實驗階段（不可重疊）
    analysis/daily_dataset.dart   分析用每日資料（身體、7 日平均、飲食總量、打勾）
    analysis/overlay_chart.dart   疊加圖資料、區間摘要
    analysis/phase_summary.dart   階段進度、執行率、每週變化
    utils/trend.dart              7 日移動平均、異常值判斷
    utils/dates.dart              當地日期、yyyy-MM-dd 日期鍵
    screens/body_screen.dart      身體組成列表（先顯示快取再同步）
    screens/food_screen.dart      單日飲食列表與總量
    screens/food_entry_sheet.dart 自訂輸入 / 編輯飲食
    screens/quick_add_sheet.dart  範本快速新增（搜尋、份量倍率、餐別）
    screens/templates_screen.dart 範本管理（釘選、編輯、封存）
    screens/trend_screen.dart     疊加趨勢圖（fl_chart）與區間摘要
    screens/phases_screen.dart    實驗階段列表、詳情、比較、表單
    widgets/phase_style.dart      階段顏色、圖表色塊
    widgets/nutrition_fields.dart 營養素輸入欄、數字格式
  test/                           單元測試 + widget 測試
    drift/                        schema migration 測試（make-migrations 產生）
  drift_schemas/                  各版 schema 快照
```

## 本地資料庫（drift）

- 資料庫檔案：App 文件目錄下的 `body_lab.sqlite`
- **健康資料快取** `daily_body_metrics`：每天一列。第一次同步抓 90 天，之後從快取最後一天
  往前 14 天重抓，並以重抓結果取代這段範圍（健康 App 裡刪掉的天也會消失）。
  讀到空資料時不動快取：iOS 被拒絕讀取時 HealthKit 只回傳空資料，和沒資料分不出來。
- **飲食紀錄** `food_entries`：時間、餐別、名稱、份量倍率，以及每份的熱量 / 蛋白質 /
  碳水 / 脂肪（都可留空），實際攝取 = 每份 × 份量。從範本加入時記錄 `template_id`，
  營養素仍複製一份，之後改範本不影響舊紀錄。
- **餐點範本** `meal_templates`（v2）：每份營養、預設份量與餐別、釘選、使用次數。
  新資料庫預設有一個釘選的「蛋白粉（1 匙）」範本（120 kcal / 24 g 蛋白質），
  數值請依自己的蛋白粉在範本管理修改。刪除範本只做封存。
- **每日打勾** `daily_checks`（v2）：目前只有肌酸，有紀錄 = 當天有吃。
- **實驗階段** `phases`（v3）：名稱、起訖日、假設、熱量 / 蛋白質目標、是否吃肌酸、心得。

### 改 schema 的流程

1. 改 `lib/data/database.dart`，`schemaVersion` +1
2. 產生程式碼與新版 schema 快照：

```bash
dart run build_runner build
```

```bash
dart run drift_dev make-migrations
```

3. 在 `migration` 的 `stepByStep` 補上新的 `fromNToN+1`
4. `flutter test test/drift` 驗證 migration

## 飲食頁怎麼用

- **+ 按鈕**：搜尋範本 → 選份量（−/+ 0.5 或 ×0.5 / ×1 / ×1.5 / ×2）與餐別 → 加入。
  找不到就按「自訂輸入」，可勾「同時存成範本」。
- **快速列**：釘選的範本一鍵 +1（後面的數字是當天已吃幾份），肌酸點一下打勾。
- **長按紀錄**：存成範本 / 編輯 / 刪除。往左滑也能刪除，都可以復原。
- 右上角書籤圖示進入範本管理：釘選、編輯、往左滑刪除。

## 趨勢頁

- 左軸：體重 / 脂肪重 / 除脂體重的 7 日平均，相對區間第一天的變化（kg）。
  三條線同一尺度，看得出體重下降是脂肪還是除脂體重。淡色點是當天實際量到的體重。
- 右軸：每日熱量或蛋白質（只畫在圖表下半部），沒紀錄的天斷開。
- 底部紫色方塊：有吃肌酸的天。
- 點圖表看當天數值；下方摘要是區間內的變化、平均攝取（只算有紀錄的天）與紀錄天數。

## 實驗頁（4 週實驗）

- 一個階段固定改變一件事，預設 4 週（可選 2 / 4 / 6 / 8 週或自訂結束日），階段不能重疊。
- 卡片顯示進度、**每週**體重 / 脂肪 / 除脂變化（長度不同的階段才能比較），以及執行率：
  熱量在目標 ±10% 內、蛋白質達到目標、有吃肌酸、有飲食紀錄的天數。
- 已進行 7 天以上的階段有兩個以上時，下方出現「階段比較」表。
- 詳情頁的圖表多顯示階段前 7 天當對照；可編輯（含心得）或刪除（只刪設定，資料保留）。
- 階段期間在趨勢圖上有背景色塊；飲食頁的總量會顯示「實際 / 目標」，達標變色。
- 變化量是「結束時 7 日平均 − 開始時 7 日平均」，開始時的平均包含階段前幾天，等於以進入階段時的狀態為基準。

## 接下來

- [x] 本地資料庫（drift）：快取健康資料 + 存飲食紀錄
- [x] 外食快速輸入：餐點範本、份量倍率、蛋白粉一鍵 +1、肌酸打勾
- [x] 疊加趨勢圖（fl_chart）
- [x] 階段（4 週實驗）功能
- [ ] 組合分析熱力圖
