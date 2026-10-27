# CLAUDE.md

## 重新部署到 iPhone（免費帳號簽署 7 天到期）

裝置：iPhone「Lantice」`00008120-0009149A2E44C01E`

```bash
cd body_lab && flutter build ios --release
xcrun devicectl device install app --device 00008120-0009149A2E44C01E build/ios/iphoneos/Runner.app
```

**不要用 `flutter install`**：它會先解除安裝舊版，App 本機資料（飲食紀錄、補充品、實驗階段）會被清掉。
`devicectl install` 是原地覆蓋升級，資料會保留。
