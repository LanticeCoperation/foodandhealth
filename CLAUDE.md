# CLAUDE.md

## 重新部署到 iPhone（免費帳號簽署 7 天到期）

裝置：iPhone「Lantice」`00008120-0009149A2E44C01E`

```bash
cd body_lab && flutter build ios --release
xcrun devicectl device install app --device 00008120-0009149A2E44C01E build/ios/iphoneos/Runner.app
```

**不要用 `flutter install`**：它會先解除安裝舊版，App 本機資料（飲食紀錄、補充品、實驗階段）會被清掉。
`devicectl install` 是原地覆蓋升級，資料會保留。

## 同步用的後端

自架的 Supabase **不在這個 repo**，在 `D:\git\supabase`（獨立 repo，之後其他專案也會共用）。
那邊有 schema 的 migrations、建帳號的 `scripts/admin.sh`，
以及兩個驗證腳本 `verify-rls.sh` / `verify-sync.sh`。說明在它的 `SELF-HOST-NOTES.md`。

App 端沒帶 `--dart-define` 的 `SUPABASE_URL` / `SUPABASE_KEY` 時，
同步功能整個關閉，行為跟加同步之前一樣。
