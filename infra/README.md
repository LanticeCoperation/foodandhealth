# infra

自架服務的部署檔案。目前只有 Supabase。

## supabase/

Body Lab 跨裝置同步與家人共享用的後端。**先在本機 Docker 開發，之後整包搬到 Synology NAS。**

### 來源與版本

- 上游：`github.com/supabase/supabase`，`docker/` 子目錄
- 釘選的 ref：**`self-hosted/v0.8.4`**（commit `189adda99d1b56da55fc5a6ee3f849354aaea92a`）
- 映像檔版本由上游 `docker-compose.yml` 釘選，**不要自己改 tag**——NAS 要跑的是同一份

相對於上游原始檔，這份只有這幾類改動：

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
| `DISABLE_SIGNUP` | `true` | **不開放對外註冊**，帳號一律由 `scripts/admin.sh` 建立 |
| `ENABLE_EMAIL_AUTOCONFIRM` | `true` | 現在其實用不到了（`admin.sh` 建帳號時直接送 `email_confirm:true`），只有舊的自助註冊流程需要。要收緊可以改回 `false` |

### 開放到外網前一定要先關掉的東西

- `DISABLE_SIGNUP=true`——**`.env.example` 的預設是 `false`**，在 NAS 上重新產 `.env` 之後
  一定要記得改，不然公開註冊是開著的。
- `ENABLE_PHONE_SIGNUP=true` 搭 `ENABLE_PHONE_AUTOCONFIRM=true` 而且沒接任何 SMS provider
  ——放到公開網址等於任何人填個手機號就能開帳號。**改成 `false`。**

### 帳號怎麼建（不開放對外註冊）

`.env` 的 `DISABLE_SIGNUP=true`，公開註冊端點會回 `422 signup_disabled`。
所有帳號都由管理端建立：

```bash
cd infra/supabase
sh scripts/admin.sh create-user someone@example.com 顯示名稱   # 密碼省略則自動產生並印出一次
sh scripts/admin.sh create-family 我家
sh scripts/admin.sh add-member 我家 someone@example.com owner
sh scripts/admin.sh list
```

其他子指令：`set-password`、`delete-user`、`remove-member`。
腳本用 `SUPABASE_SECRET_KEY` 打 auth 的 admin API，再用 `psql` 寫 profile 與成員，
**不依賴 jq / node**，NAS 上可以直接跑。Studio 的 Authentication 頁面也能建帳號，
但那樣不會一併建 `profiles` 那一列，建議統一走腳本。

因為帳號由管理端建，所以**沒有邀請碼、沒有 join_family RPC**——
使用者自助加入家庭的那一整套 RLS 風險面直接消失了。

### 資料庫 migration

`migrations/0001_identity.sql` 建了 `profiles`、`families`、`family_members` 與 RLS。
資料表（飲食、體重……）等 drift schema 12 一起設計，之後才進 `0002`。

驗證 RLS 真的有隔開：

```bash
sh scripts/verify-rls.sh
```

會自己建三個測試帳號（兩個同家庭、一個在外面）跑 14 項檢查，跑完自動刪掉。
**搬到 NAS 之後要再跑一次。**

幾個實測確認的點，之後寫 `0002` 時要沿用：

- `public` schema 的 default privileges **會自動把 ALL 權限給 `anon` 和 `authenticated`**。
  新表預設是全開的，擋住它的只有 RLS。所以每張表都要
  `revoke all ... from anon`（第二道防線）+ `enable row level security` + 寫好 policy。
- policy 用的輔助函式放在 `private` schema。放 `public` 的話，
  default privileges 會把 EXECUTE 給 `anon`，而且 `PGRST_DB_SCHEMAS` 會把它變成
  `/rest/v1/rpc/...` 端點。
- 查 `family_members` 的 policy 必須走 `security definer` 函式，否則會無限遞迴。
- `postgres` 在這個映像檔裡**不是 superuser**，`auth` schema 屬於 `supabase_admin`，
  所以不要想在 `auth.users` 上掛觸發器。
- 套用 migration 一定要帶 `-v ON_ERROR_STOP=1`，否則 psql 會略過錯誤繼續跑，
  留下套到一半的 schema。檔尾要 `notify pgrst, 'reload schema';`，不然 REST 會一直回 PGRST205。

Git Bash 的 curl 在 `-d` 直接帶非 ASCII 字串時，PostgREST 會回 `PGRST102`
（`Empty or invalid json`）——同樣的內容改走 `--data-binary @檔案` 就正常。
推測是 ucrt64 的 `curl.exe` 用 ANSI code page 轉參數所致；透過 `docker exec` 的 psql
處理中文則沒問題。測試腳本因此一律用 ASCII 測試資料，免得測到 shell 的毛病而不是 API 的。

### 登入方式的選項（第一版用 Email 密碼）

不管用哪一種，識別資料歸屬的 ID 都是 **`auth.users.id`**（UUID），不會因為換登入方式而變。
**不要在裝置端自己產生 owner ID**，否則會變成兩套 ID 空間。

**Email + 密碼**：現在就能用，LAN 上直接通，不需要任何外部設定。
代價是這個 stack 沒有 SMTP，使用者無法自助重設密碼，要由管理者在 Studio 改。

**Google 登入**：手機上走的是 **ID Token flow**，不是瀏覽器轉址流程——
`google_sign_in` 在裝置上拿到 ID token，再用 `signInWithIdToken` 打
`/auth/v1/token?grant_type=id_token`。Google 不會回呼 `API_EXTERNAL_URL`，
**所以 `API_EXTERNAL_URL` 是 localhost 也不影響**，不必等 NAS 和公開 HTTPS。

啟用時的地雷：

- `docker-compose.yml` 註解裡的 `GOTRUE_EXTERNAL_SKIP_NONCE_CHECK` **無效**。
  CONFIG.md 明寫它「does not map to a configuration field」，要用的是
  **`GOTRUE_EXTERNAL_GOOGLE_SKIP_NONCE_CHECK`**。照著 compose 的註解做會卡住。
- `GOTRUE_EXTERNAL_ALLOWED_ID_TOKEN_ISSUERS` 的預設值已含
  `https://accounts.google.com`，不用另外設。
- 取消註解 Google 那幾行會成為第 4 項對上游的改動，記得補在上面。

Google Cloud Console 那邊要自己建（三個 client）：

| 類型 | 用途 |
|---|---|
| **Web** | client ID 同時填進伺服器的 `GOOGLE_CLIENT_ID` 與 App 的 `serverClientId`，token 的 audience 才對得上 |
| **iOS** | reversed client ID 要寫進 Info.plist 當 URL scheme（免費個人帳號可以） |
| **Android** | 要填 package name + **CI 簽 release APK 用的 keystore SHA-1**；本機 debug build 要另外加 debug SHA-1。這步最常漏 |

OAuth consent screen 若停在 testing 模式，記得把家人的 email 加進測試使用者。

**之後可以補上 Google 而不換 uid**：`linkIdentity` 需要
`GOTRUE_SECURITY_MANUAL_LINKING_ENABLED`（CONFIG.md 列的預設是 `false`）。
也就是說先用 Email 密碼上線、之後再掛 Google，不是單行道。

**不要用匿名登入。** session 掉了（例如 `flutter install` 清掉 App 資料）伺服器那份就變孤兒，
而且等於對外開放免憑證註冊。

### 搬到 Synology 時

- **`.env` 不在 git 裡**（內含金鑰）。NAS 上請**重新產生一份，不要複製本機這份**：

  ```bash
  cp .env.example .env && sh utils/generate-keys.sh --update-env && sh utils/add-new-auth-keys.sh --update-env
  ```

  產完金鑰後**立刻把 `DISABLE_SIGNUP` 改成 `true`、`ENABLE_PHONE_SIGNUP` 改成 `false`**，
  `.env.example` 的預設值是開放註冊的。
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
