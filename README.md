# Body Lab

從 Apple 健康（iOS）/ Health Connect（Android）讀取**體重、體脂%、除脂體重**與
**Apple Watch 活動消耗**，搭配飲食紀錄、補充品打勾與 4 週實驗階段，
看哪種做法真的讓脂肪下降、除脂體重上升。

- **身體**：每天只取最早一筆（起床測量），算脂肪重與 7 日移動平均，標出水分波動
- **飲食**：選餐別、輸入熱量（蛋白質 / 脂肪選填）；蛋白粉一鍵 +1、肌酸打勾；
  對照每日消耗（基礎代謝 + Apple Watch 活動消耗）顯示赤字 / 盈餘
- **趨勢**：體重 / 脂肪 / 除脂變化疊加每日熱量與每日消耗
- **分析**：4 週實驗階段（目標、執行率、階段比較）與組合分析熱力圖

## 在 Mac 上跑起來（iPhone 實機）

```bash
git clone https://github.com/LanticeCoperation/foodandhealth.git
```

```bash
cd foodandhealth/body_lab && flutter pub get && flutter test
```

```bash
open ios/Runner.xcworkspace
```

在 Xcode：

1. 左側選 **Runner** 專案 → TARGETS **Runner** → **Signing & Capabilities**
2. **Team** 選你的 Apple ID / 開發者帳號
3. **Bundle Identifier** 改成自己的（例如 `com.<你的名字>.bodylab`）；`com.yourname.bodyLab`
   很可能已被別人註冊而無法簽署
4. 確認 capability 列表裡有 **HealthKit**（entitlement 已經設好，沒出現就 `+ Capability` 加一次）。
   免費 Apple ID 若無法簽署 HealthKit，需要改用付費開發者帳號

接上 iPhone（第一次要在 iPhone 上開啟「開發者模式」），然後：

```bash
flutter run
```

- 免費帳號第一次安裝後，到 iPhone 的 設定 → 一般 → VPN 與裝置管理 信任開發者
- 只能用**實機**：模擬器沒有你的健康資料
- 第一次開啟會跳出健康權限畫面，把體重、體脂率、除脂體重、活動能量都打開。之後要改權限：
  設定 → 健康 → 資料存取與裝置 → Body Lab
- iOS 已設定：Info.plist 權限說明、`Runner.entitlements`（HealthKit）、部署目標 iOS 15.0

## Android（Health Connect）

已設定：`minSdk = 26`、Health Connect 讀取權限（體重 / 體脂 / 除脂體重 / 活動消耗 / 歷史資料）、
權限說明 intent-filter、`ViewPermissionUsageActivity`、`FlutterFragmentActivity`。
`android/gradle.properties` 的 `kotlin.incremental=false` 是因為 Windows 上專案與 pub cache
在不同磁碟時 Kotlin 增量編譯會失敗。

Android 14 以上 Health Connect 內建在系統；Android 13 以下要從 Play 商店安裝
（App 偵測到沒安裝會顯示安裝按鈕）。Health Connect 預設只給授權後 30 天的資料，
App 會另外要求「讀取歷史資料」權限以取得 90 天。

上架前把 `com.yourname` 換成自己的（Android `applicationId` / `namespace` / MainActivity
package、iOS Bundle Identifier）。

## 怎麼用

### 身體

每天一列：體重、體脂、脂肪重、除脂體重與 7 日平均。偏離 7 日平均超過 0.8 kg 的天標記水滴
（多半是水分）。除脂體重後面有「*推算」表示體脂計沒寫入，由 體重 × (1 − 體脂%) 算出。
先顯示本地快取，再背景同步；右上角可手動同步。

### 個人資料與每日消耗（身體頁右上角人像）

- 輸入性別、年齡、身高、活動量；體重預設最近的 7 日平均。用 Mifflin-St Jeor 算基礎代謝，
  × 活動量得到 TDEE，存下來後固定使用（體重變化 2–3 kg 以上再回來重算）。
- **每日消耗怎麼算**（預設 Apple Watch）：
  - **Apple Watch 活動消耗**：每天 = 基礎代謝 + 當天手錶記錄的活動消耗；沒戴手錶的天用 TDEE
  - **固定 TDEE**：每天都用 TDEE（活動量係數已包含運動，不再加手錶消耗，避免重複計算）
- 活動消耗用 HealthKit 統計查詢 / Health Connect 聚合查詢讀取每日總和，已依來源去重
  （iPhone 與手錶同時記錄不會加兩次）。

### 資料備份（iPhone）

個人資料頁（身體頁右上角人像）最下方：

- **匯出**：產生 `body_lab_backup_日期.json`，分享選單選「儲存到檔案 → iCloud Drive」
  （或 Google Drive 等任何地方）。
- **從檔案匯入**：從「檔案」App 選備份檔，確認後**取代**目前的飲食紀錄、一鍵項目、打勾、
  階段與個人資料；身體組成與活動消耗不在備份內，會從 Apple 健康重新同步。
- iPhone 開著 iCloud 備份時，App 資料庫本身也會一起備份（換新手機從 iCloud 還原就會回來），
  但刪掉 App 重裝不會，所以建議定期匯出。
- 正式版只在 iOS 顯示；debug 版的 Android 也顯示，方便在模擬器測試。

### 飲食

- **記錄**：選早餐 / 午餐 / 晚餐 / 點心（預設依時間），輸入熱量就能存；蛋白質、脂肪選填。
- **快速列**：釘選項目一鍵 +1（後面的數字是當天已吃幾份），肌酸點一下打勾。
  預設「蛋白粉（1 匙）」60 kcal / 12 g 蛋白質，可在右上角閃電圖示（一鍵 +1 項目）依包裝標示修改。
- 點紀錄可編輯；往左滑刪除，提示 4 秒內可復原。
- 總量卡片：熱量 / 蛋白質對照階段目標的進度條（達標綠色、未達紅色），
  以及當天消耗與赤字 / 盈餘（今天的活動消耗會標「到目前」）。

### 趨勢

- 左軸：體重 / 脂肪重 / 除脂體重的 7 日平均，相對區間第一天的變化（kg）。
  三條線同一尺度，看得出體重下降是脂肪還是除脂體重。淡色點是當天實際量到的體重。
- 下半部：每日熱量或蛋白質（灰柱）；顯示熱量時虛線是每日消耗，灰柱低於虛線就是赤字。
- 底部紫色方塊：有吃肌酸的天；背景色塊：實驗階段。
- 點圖表看當天數值；下方摘要是區間內的變化、平均攝取與平均熱量差（只算有紀錄的天）、紀錄天數。

### 分析 → 實驗階段

- 一個階段固定改變一件事，預設 4 週（可選 2 / 4 / 6 / 8 週或自訂結束日），階段不能重疊。
- 卡片顯示進度、**每週**體重 / 脂肪 / 除脂變化（長度不同的階段才能比較），以及執行率：
  熱量在目標 ±10% 內、蛋白質達到目標、有吃肌酸、有飲食紀錄的天數。
- 已進行 7 天以上的階段有兩個以上時，下方出現「階段比較」表。
- 詳情頁的圖表多顯示階段前 7 天當對照；可編輯（含心得）或刪除（只刪設定，資料保留）。
- 變化量是「結束時 7 日平均 − 開始時 7 日平均」，開始時的平均包含階段前幾天，
  等於以進入階段時的狀態為基準。

### 分析 → 組合分析

- 把全部歷史從今天往回切成不重疊的**週**，每週一個樣本：
  - 因子：平均熱量、蛋白質 g/kg、肌酸（一週 ≥5 天算有）、階段（一週 ≥4 天在該階段）
  - 結果：體重 / 脂肪重 / 除脂體重的 7 日平均，這週末減上週末
- 選橫軸、縱軸兩個因子（縱軸可選「不分」看單一因子），每格是該組合各週的平均變化與週數 n。
  綠色是好的方向（脂肪、體重下降；除脂體重上升），n 少於 2 的格子淡化。
- 熱量依該週平均每日赤字（攝取 − 當天消耗）分成「赤字 >500 / 赤字 0–500 / 盈餘」；
  還沒設定個人資料時改用自己資料的三分位數。蛋白質依 1.2 / 1.6 / 2.2 g/kg 分組。
- 用到熱量 / 蛋白質時，一週需至少 4 天飲食紀錄；週變化需要這週與上週末的 7 日平均
  都至少有 3 次量測。
- 用週而不用逐日滑動，是因為逐日樣本彼此重疊，n 會灌水。這是相關不是因果。
- 下方「各週資料」可以看每一週的原始數字。

## 專案結構

```
body_lab/
  lib/
    main.dart                     AppServices（資料庫、repository）、底部頁籤
    models/body_metric.dart       每日身體組成資料
    services/health_service.dart  HealthKit / Health Connect 讀取、每日取第一筆
    data/database.dart            drift schema 與 migration
    data/body_repository.dart     健康資料快取、同步
    data/food_repository.dart     飲食紀錄 CRUD、每日總量
    data/template_repository.dart 餐點範本、從範本加入
    data/check_repository.dart    每日打勾（肌酸）
    data/phase_repository.dart    實驗階段（不可重疊）
    data/profile_repository.dart  個人資料（只有一列）
    data/activity_repository.dart 每日活動消耗快取、同步
    data/backup_service.dart      JSON 備份匯出 / 匯入（帶格式版本）
    analysis/daily_dataset.dart   分析用每日資料（身體、7 日平均、飲食、打勾、階段）
    analysis/overlay_chart.dart   疊加圖資料、區間摘要
    analysis/phase_summary.dart   階段進度、執行率、每週變化
    analysis/combo_heatmap.dart   週樣本、因子分組、熱力圖
    analysis/tdee.dart            Mifflin-St Jeor 基礎代謝、TDEE
    analysis/energy.dart          每日消耗（基礎代謝 + 手錶活動消耗 / 固定 TDEE）
    utils/trend.dart              7 日移動平均、異常值判斷
    utils/dates.dart              當地日期、yyyy-MM-dd 日期鍵
    screens/body_screen.dart      身體組成列表
    screens/food_screen.dart      單日飲食、快速列
    screens/food_entry_sheet.dart 自訂輸入 / 編輯飲食
    screens/templates_screen.dart 一鍵 +1 項目
    screens/profile_screen.dart   個人資料與每日消耗設定
    screens/trend_screen.dart     疊加趨勢圖（fl_chart）與區間摘要
    screens/analysis_screen.dart  分析頁（實驗階段 / 組合分析）
    screens/phases_screen.dart    實驗階段列表、詳情、比較、表單
    screens/combo_screen.dart     組合分析熱力圖
    widgets/nutrition_fields.dart 營養素輸入欄、數字格式
    widgets/phase_style.dart      階段顏色、圖表色塊
    widgets/undo_snackbar.dart    4 秒自動消失的復原提示
    widgets/backup_section.dart   備份區塊（分享選單匯出、檔案選擇器匯入）
    theme/app_theme.dart          主題與 AppPalette（圖表 / 語意用色，深淺色各一套）
    dev/demo_data.dart            debug 版示範資料（身體頁 🐞）
  test/                           單元測試 + widget 測試（手機尺寸 360 × 780）
    drift/                        schema migration 測試（make-migrations 產生）
  drift_schemas/                  各版 schema 快照
```

## 本地資料庫（drift）

資料庫檔案在 App 文件目錄下的 `body_lab.sqlite`，目前 schema v5。

- **健康資料快取** `daily_body_metrics`：每天一列。第一次同步抓 90 天，之後從快取最後一天
  往前 14 天重抓，並以重抓結果取代這段範圍（健康 App 裡刪掉的天也會消失）。
  讀到空資料時不動快取：iOS 被拒絕讀取時 HealthKit 只回傳空資料，和沒資料分不出來。
- **飲食紀錄** `food_entries`：時間、餐別、名稱、份量倍率，以及每份的熱量 / 蛋白質 /
  碳水 / 脂肪（都可留空），實際攝取 = 每份 × 份量。從範本加入時記錄 `template_id`，
  營養素仍複製一份，之後改範本不影響舊紀錄。
- **餐點範本** `meal_templates`（v2）：每份營養、預設份量與餐別、釘選、使用次數。刪除只做封存。
- **每日打勾** `daily_checks`（v2）：目前只有肌酸，有紀錄 = 當天有吃。
- **實驗階段** `phases`（v3）：名稱、起訖日、假設、熱量 / 蛋白質目標、是否吃肌酸、心得。
- **個人資料** `profiles`（v4，只有一列）：性別、出生年、身高、活動量、計算時體重、固定 TDEE，
  每日消耗算法 `energy_mode`（v5）。
- **活動消耗快取** `daily_activity`（v5）：每天一列。首次同步 90 天，之後從最後一天往前 3 天重抓
  （今天的消耗會持續增加）；讀到空資料時不動快取。

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
4. 驗證 migration：

```bash
flutter test test/drift
```

## 進度

- [x] 讀取身體組成（HealthKit / Health Connect）
- [x] 本地資料庫（drift）：快取健康資料 + 存飲食紀錄
- [x] 外食快速輸入：餐點範本、份量倍率、蛋白粉一鍵 +1、肌酸打勾
- [x] 疊加趨勢圖（fl_chart）
- [x] 階段（4 週實驗）功能
- [x] 組合分析熱力圖
- [x] 資料備份：匯出到 iCloud Drive / 從檔案匯入
- [ ] iPhone 實機驗證
