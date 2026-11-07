# infra

自架服務的部署檔案。目前只有 Supabase。

## supabase/

Body Lab 跨裝置同步與家人共享用的後端。**先在本機 Docker 開發，之後整包搬到 Synology NAS。**

### 來源與版本

- 上游：`github.com/supabase/supabase`，`docker/` 子目錄
- 釘選的 ref：**`self-hosted/v0.8.4`**（commit `189adda99d1b56da55fc5a6ee3f849354aaea92a`）
- 映像檔版本由上游 `docker-compose.yml` 釘選，**不要自己改 tag**——NAS 要跑的是同一份

相對於上游原始檔，這份只有兩類改動：

1. `utils/add-new-auth-keys.sh` 自動取消註解了 4 行（啟用非對稱金鑰）：
   `GOTRUE_JWT_KEYS`、`API_JWT_JWKS`、`JWT_JWKS`、`SUPABASE_JWKS`
2. `.env` 的開發用設定（見下）
3. `.gitignore` 多加一行 `.env.old`——`utils/generate-keys.sh` 用 `sed -i.old` 改 `.env`，
   會留下一份**含真實金鑰**的 `.env.old` 且不會自己刪掉。NAS 上產金鑰時同樣會留，記得清掉。

### 本機啟動

```bash
cd infra/supabase && sh run.sh start
```

其他常用指令：`sh run.sh status` / `logs [service]` / `stop` / `secrets`。

- API gateway：http://localhost:8000
- Studio：同樣 http://localhost:8000（basic auth，帳密看 `sh run.sh secrets`）
- Postgres：`localhost:5432`，經由 Supavisor session pooler。
  **使用者名稱是 `postgres.bodylab`**（`postgres.<POOLER_TENANT_ID>`），不是 `postgres`。
  直接對容器下 SQL 則用 `docker compose exec db psql -U postgres`，不經過 pooler。

**不要執行 `reset.sh`，它會清掉資料庫。**

### 加 compose override 的正確方式

`.env` 裡有設 `COMPOSE_FILE`，**一旦設了，compose 就不會再自動載入
`docker-compose.override.yml`**。要加 override 必須走：

```bash
sh run.sh config add override
```

這會把檔名寫進 `.env` 的 `COMPOSE_FILE`。直接丟一個 override 檔在資料夾裡不會生效。

（Windows 本機若 `volumes/db/data` 這個 bind mount 讓 Postgres initdb 失敗——
`docker compose logs db` 會看到權限/擁有者錯誤加上重啟迴圈——就用 override 把
`/var/lib/postgresql/data` 換成 named volume，停掉、刪掉半套的 `volumes/db/data`、再啟動。
本機這台 Windows 實測不需要 override，bind mount 直接就起來了。
NAS 若遇到同樣問題——Synology 共享資料夾有 ACL，PGDATA 放 bind mount 上可能會踩到
——就在那邊另外建一個 override 並用 `sh run.sh config add override` 掛上，
不要把本機的 override 複製過去，那個檔案是 gitignore 的。）

### 驗證方式（本機已通過）

App 端用的是 `SUPABASE_PUBLISHABLE_KEY`（`sb_publishable_…` 這種不透明金鑰），
不是舊的 `ANON_KEY`。Envoy 會把它換成內部的 ES256 JWT，所以要測的是這條路徑：

| 檢查 | 預期 |
|---|---|
| `GET /rest/v1/<table>` 帶 publishable key | 通過 gateway（表不存在時是 404） |
| 同上但 key 亂填 | 401 |
| 不帶 key | 401 |
| `POST /auth/v1/signup` | 直接回 `access_token`（autoconfirm 生效） |
| 該 token 的 header | `"alg":"ES256"`（非對稱金鑰生效） |
| `GET /auth/v1/user` 帶該 token | 200 |
| Studio `/` 不帶 basic auth | 401 |

**`GET /rest/v1/`（根路徑）回 403 `RBAC: access denied` 是正常的**，那是 Envoy 擋掉
anon 讀 OpenAPI spec，不是設定錯誤。別拿根路徑當健康檢查。

基礎 stack 是 11 個服務；analytics（Logflare）與 vector 在 `docker-compose.logs.yml`
這個 override 裡，預設沒啟用。

### .env 的開發用設定

`.env` 由 `.env.example` 複製後，用 `utils/generate-keys.sh` 與 `utils/add-new-auth-keys.sh`
產生金鑰，另外手動改了兩項：

| 變數 | 值 | 原因 |
|---|---|---|
| `POOLER_TENANT_ID` | `bodylab` | 上游預設是佔位字串 |
| `ENABLE_EMAIL_AUTOCONFIRM` | `true` | **開發用**。這個 stack 沒有 mail 服務（`SMTP_HOST=supabase-mail` 指向不存在的容器），不自動確認的話註冊會卡住 |

正式上線前要把 `ENABLE_EMAIL_AUTOCONFIRM` 改回 `false` 並接上真的 SMTP。

### 開放到外網前一定要先關掉的東西

- `ENABLE_PHONE_SIGNUP=true` 搭 `ENABLE_PHONE_AUTOCONFIRM=true` 而且沒接任何 SMS provider
  ——放到公開網址等於任何人填個手機號就能開帳號。**改成 `false`。**
- 家人的帳號都建好之後，直接 `DISABLE_SIGNUP=true` 最乾淨。
- `ENABLE_EMAIL_AUTOCONFIRM` 改回 `false`。

### 搬到 Synology 時

- **`.env` 不在 git 裡**（內含金鑰）。NAS 上請**重新產生一份，不要複製本機這份**：

  ```bash
  cp .env.example .env && sh utils/generate-keys.sh --update-env && sh utils/add-new-auth-keys.sh --update-env
  ```

  本機這組密碼在開發過程中被印到終端機過，當成「只在本機用」處理就好。
  目前還沒有任何 App build 內嵌金鑰，現在換零成本。
  之後 App 端填的是 `SUPABASE_PUBLISHABLE_KEY`，NAS 換金鑰時那邊要跟著改。
- **整個 `supabase/` 資料夾都要帶**，不是只有 `docker-compose.yml`。
  compose 會 bind-mount `./volumes/...` 底下的 Envoy 設定、DB init SQL、vector 設定等等，少了就起不來。
- **schema 與 RLS policy 一律寫成 `migrations/*.sql` 版控**，用
  `docker compose exec db psql` 套用。只在 Studio 點一點的東西不會跟著走，NAS 重建時會缺。
- 資料目錄（`volumes/db/data`、`volumes/storage`）是 gitignore 的本機狀態，不要複製，
  要搬資料請用 `pg_dump`。
- NAS 規格要先確認：整套 stack 吃好幾 GB 記憶體，且不少 ARM 機種的 Container Manager
  跑不起來。真的卡，再考慮拿掉 analytics/vector、imgproxy、functions 這幾個服務。

### 更新上游

```bash
cd infra/supabase && sh update.sh --dry-run
```

`.supabase-version` 記錄了當初的 base ref，`update.sh` 用它做三方合併。
