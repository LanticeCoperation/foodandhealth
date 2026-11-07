#!/bin/sh
#
# 模擬「同一個人兩支手機 + 家人 + 外人」，驗證 0002 的同步語意。
#
#   sh scripts/verify-sync.sh
#
# 兩支手機 = 同一個帳號登入兩次拿到兩個 token。
# 測試資料一律 ASCII，body 走 --data-binary @檔案（Git Bash 的 curl 直接帶非 ASCII 會壞）。
# 跑完自動刪掉測試帳號與資料。

set -e
cd "$(dirname "$0")/.."

env_get() { grep "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r"'"'"; }
PUB=$(env_get SUPABASE_PUBLISHABLE_KEY)
BASE=$(env_get SUPABASE_PUBLIC_URL)
[ -n "$BASE" ] || BASE="http://localhost:8000"

FAMILY="SyncFam-$$"
PW="sync-$(openssl rand -hex 8)"
A="synctest-a-$$@example.com"
B="synctest-b-$$@example.com"
C="synctest-c-$$@example.com"
TMP=$(mktemp -d)

PASS=0; FAIL=0
check() {
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s （預期 %s，實得 %s）\n' "$1" "$2" "$3"; fi
}

cleanup() {
  for e in "$A" "$B" "$C"; do sh scripts/admin.sh delete-user "$e" >/dev/null 2>&1 || true; done
  psql_q "delete from public.families where name = '$FAMILY'" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

psql_q() { docker compose exec -T db psql -U postgres -d postgres -qtAc "$1" | tr -d '\r'; }

login() {
  printf '{"email":"%s","password":"%s"}' "$1" "$PW" > "$TMP/login.json"
  curl -s -X POST "$BASE/auth/v1/token?grant_type=password" -H "apikey: $PUB" \
       -H "Content-Type: application/json" --data-binary @"$TMP/login.json" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

# send <token> <method> <path> <body-file> [extra-header...] -> 印出回應內容
send() {
  _t="$1"; _m="$2"; _p="$3"; _f="$4"; shift 4
  curl -s -X "$_m" -H "apikey: $PUB" -H "Authorization: Bearer $_t" \
       -H "Content-Type: application/json" "$@" \
       --data-binary @"$_f" "$BASE/rest/v1/$_p"
}

send_code() {
  _t="$1"; _m="$2"; _p="$3"; _f="$4"; shift 4
  curl -s -o /dev/null -w '%{http_code}' -X "$_m" -H "apikey: $PUB" -H "Authorization: Bearer $_t" \
       -H "Content-Type: application/json" "$@" \
       --data-binary @"$_f" "$BASE/rest/v1/$_p"
}

count_rows() {
  curl -s -D - -o /dev/null -H "apikey: $PUB" -H "Authorization: Bearer $1" \
       -H "Prefer: count=exact" "$BASE/rest/v1/$2" \
    | tr -d '\r' | sed -n 's|^[Cc]ontent-[Rr]ange: .*/||p'
}

echo "建立測試資料…"
sh scripts/admin.sh create-user "$A" PhoneOwner "$PW" >/dev/null
sh scripts/admin.sh create-user "$B" FamilyB    "$PW" >/dev/null
sh scripts/admin.sh create-user "$C" Outsider   "$PW" >/dev/null
sh scripts/admin.sh create-family "$FAMILY" >/dev/null
sh scripts/admin.sh add-member "$FAMILY" "$A" owner >/dev/null
sh scripts/admin.sh add-member "$FAMILY" "$B" >/dev/null

# 同一個帳號登入兩次 = 兩支手機
P1=$(login "$A"); P2=$(login "$A"); TB=$(login "$B"); TC=$(login "$C")
[ -n "$P1" ] && [ -n "$P2" ] && [ -n "$TB" ] && [ -n "$TC" ] || { echo "登入失敗" >&2; exit 1; }
UID_B=$(psql_q "select id from auth.users where email = '$B'" | tr -d ' ')

S1=$(psql_q "select gen_random_uuid()" | tr -d ' ')
S2=$(psql_q "select gen_random_uuid()" | tr -d ' ')
S3=$(psql_q "select gen_random_uuid()" | tr -d ' ')

cat > "$TMP/batch.json" <<JSON
[{"sync_id":"$S1","eaten_at":"2026-11-07T08:00:00Z","meal":"breakfast","name":"Oatmeal","servings":1,"kcal":350,"created_at":"2026-11-07T08:00:00Z"},
 {"sync_id":"$S2","eaten_at":"2026-11-07T12:30:00Z","meal":"lunch","name":"Chicken rice","servings":1,"kcal":700,"created_at":"2026-11-07T12:30:00Z"},
 {"sync_id":"$S3","eaten_at":"2026-11-07T19:00:00Z","meal":"dinner","name":"Salad","servings":2,"kcal":420,"created_at":"2026-11-07T19:00:00Z"}]
JSON

echo "1 手機一上傳、手機二下拉"
send_code "$P1" POST 'food_entries?on_conflict=sync_id' "$TMP/batch.json" \
  -H "Prefer: resolution=merge-duplicates" > "$TMP/code" 2>/dev/null || true
check "手機一上傳 3 筆" 201 "$(cat "$TMP/code")"
check "手機二看得到 3 筆" 3 "$(count_rows "$P2" 'food_entries?select=sync_id')"

echo "2 重送同一批（模擬網路不穩重試）"
send_code "$P1" POST 'food_entries?on_conflict=sync_id' "$TMP/batch.json" \
  -H "Prefer: resolution=merge-duplicates" >/dev/null
check "還是 3 筆，沒有重複" 3 "$(count_rows "$P2" 'food_entries?select=sync_id')"

echo "3 手機二改一筆，手機一增量下拉"
# psql 預設輸出是 "2026-11-07 03:12:34.56+00"，有空白和 + 號，不能直接塞進 URL。
# 轉成 ISO8601 的 Z 形式。
CURSOR=$(psql_q "select to_char(max(updated_at) at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') from public.food_entries" | tr -d ' ')
printf '{"kcal":800}' > "$TMP/patch.json"
send "$P2" PATCH "food_entries?sync_id=eq.$S2" "$TMP/patch.json" -H "Prefer: return=minimal" >/dev/null
check "手機一用舊游標只抓到 1 筆" 1 "$(count_rows "$P1" "food_entries?select=sync_id&updated_at=gt.$CURSOR")"
check "改到的是那一筆" "800" "$(psql_q "select kcal::int from public.food_entries where sync_id='$S2'" | tr -d ' ')"

echo "4 用戶端謊報 updated_at"
cat > "$TMP/liar.json" <<JSON
[{"sync_id":"$S1","eaten_at":"2026-11-07T08:00:00Z","meal":"breakfast","name":"Oatmeal","servings":1,"kcal":351,"created_at":"2026-11-07T08:00:00Z","updated_at":"2000-01-01T00:00:00Z"}]
JSON
send_code "$P1" POST 'food_entries?on_conflict=sync_id' "$TMP/liar.json" \
  -H "Prefer: resolution=merge-duplicates" >/dev/null
check "伺服器用自己的時間，不理會 2000 年" "2026" \
  "$(psql_q "select extract(year from updated_at)::int from public.food_entries where sync_id='$S1'" | tr -d ' ')"

echo "5 軟刪除"
printf '{"deleted_at":"2026-11-07T20:00:00Z"}' > "$TMP/del.json"
send "$P1" PATCH "food_entries?sync_id=eq.$S3" "$TMP/del.json" -H "Prefer: return=minimal" >/dev/null
check "手機二看得到墓碑（列還在）" 3 "$(count_rows "$P2" 'food_entries?select=sync_id')"
check "手機二過濾未刪除的剩 2 筆" 2 "$(count_rows "$P2" 'food_entries?select=sync_id&deleted_at=is.null')"

echo "6 家人唯讀"
check "家人 B 讀得到 A 的 3 筆" 3 "$(count_rows "$TB" 'food_entries?select=sync_id')"
printf '{"kcal":1}' > "$TMP/bpatch.json"
check "家人 B 改不動（影響 0 列）" "[]" \
  "$(send "$TB" PATCH "food_entries?sync_id=eq.$S1" "$TMP/bpatch.json" -H "Prefer: return=representation")"
cat > "$TMP/bsteal.json" <<JSON
[{"sync_id":"$S1","eaten_at":"2026-11-07T08:00:00Z","meal":"breakfast","name":"Stolen","servings":1,"created_at":"2026-11-07T08:00:00Z"}]
JSON
send_code "$TB" POST 'food_entries?on_conflict=sync_id' "$TMP/bsteal.json" \
  -H "Prefer: resolution=merge-duplicates" > "$TMP/code2" 2>/dev/null || true
check "家人 B 用 A 的 sync_id upsert 被擋" 403 "$(cat "$TMP/code2")"
check "A 的那筆沒被改名" "Oatmeal" "$(psql_q "select name from public.food_entries where sync_id='$S1'" | tr -d ' ')"

echo "7 外人"
check "外人 C 一筆都看不到" 0 "$(count_rows "$TC" 'food_entries?select=sync_id')"

echo "8 不能假冒別人寫入"
S4=$(psql_q "select gen_random_uuid()" | tr -d ' ')
cat > "$TMP/forge.json" <<JSON
[{"sync_id":"$S4","user_id":"$UID_B","eaten_at":"2026-11-07T08:00:00Z","meal":"snack","name":"Forged","servings":1,"created_at":"2026-11-07T08:00:00Z"}]
JSON
send_code "$P1" POST 'food_entries' "$TMP/forge.json" > "$TMP/code3" 2>/dev/null || true
check "A 冒用 B 的 user_id 寫入被擋" 403 "$(cat "$TMP/code3")"

echo "9 硬刪除不開放"
check "DELETE 被擋（刪除只能走 deleted_at）" 403 \
  "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "apikey: $PUB" \
      -H "Authorization: Bearer $P1" "$BASE/rest/v1/food_entries?sync_id=eq.$S1")"

echo "10 自然鍵的表（daily_checks：user_id + day + item）"
cat > "$TMP/check.json" <<JSON
[{"day":"2026-11-07","item":"creatine","checked_at":"2026-11-07T09:00:00Z","amount":5}]
JSON
send_code "$P1" POST 'daily_checks?on_conflict=user_id,day,item' "$TMP/check.json"   -H "Prefer: resolution=merge-duplicates" > "$TMP/c1" 2>/dev/null || true
check "手機一打勾" 201 "$(cat "$TMP/c1")"
send_code "$P2" POST 'daily_checks?on_conflict=user_id,day,item' "$TMP/check.json"   -H "Prefer: resolution=merge-duplicates" >/dev/null
check "手機二打同一天同一項，還是 1 列" 1 "$(count_rows "$P1" 'daily_checks?select=day')"

printf '{"deleted_at":"2026-11-07T20:00:00Z"}' > "$TMP/uncheck.json"
send "$P1" PATCH "daily_checks?day=eq.2026-11-07&item=eq.creatine" "$TMP/uncheck.json"   -H "Prefer: return=minimal" >/dev/null
check "取消打勾留下墓碑" 1   "$(count_rows "$P1" 'daily_checks?select=day&deleted_at=not.is.null')"

cat > "$TMP/recheck.json" <<JSON
[{"day":"2026-11-07","item":"creatine","checked_at":"2026-11-07T21:00:00Z","amount":5,"deleted_at":null}]
JSON
send_code "$P1" POST 'daily_checks?on_conflict=user_id,day,item' "$TMP/recheck.json"   -H "Prefer: resolution=merge-duplicates" >/dev/null
check "重新打勾把墓碑救回來" 0   "$(count_rows "$P1" 'daily_checks?select=day&deleted_at=not.is.null')"
check "家人看得到打勾" 1 "$(count_rows "$TB" 'daily_checks?select=day')"
check "外人看不到" 0 "$(count_rows "$TC" 'daily_checks?select=day')"

echo "11 單列的表（body_profiles：一個人一列）"
cat > "$TMP/prof.json" <<JSON
[{"sex":"male","birth_year":1988,"height_cm":172,"activity":"moderate","weight_kg":74.5,"tdee_kcal":2400,"energy_mode":"watch"}]
JSON
send_code "$P1" POST 'body_profiles?on_conflict=user_id' "$TMP/prof.json"   -H "Prefer: resolution=merge-duplicates" > "$TMP/c2" 2>/dev/null || true
check "手機一寫入個人資料" 201 "$(cat "$TMP/c2")"
cat > "$TMP/prof2.json" <<JSON
[{"sex":"male","birth_year":1988,"height_cm":172,"activity":"moderate","weight_kg":73.0,"tdee_kcal":2380,"energy_mode":"watch"}]
JSON
send_code "$P2" POST 'body_profiles?on_conflict=user_id' "$TMP/prof2.json"   -H "Prefer: resolution=merge-duplicates" >/dev/null
check "手機二更新，還是 1 列" 1 "$(count_rows "$P1" 'body_profiles?select=user_id')"
check "值是後寫的那個" "73"   "$(psql_q "select weight_kg::int from public.body_profiles where user_id=(select id from auth.users where email='$A')" | tr -d ' ')"

echo "12 健康快取只上傳（body_metrics）"
cat > "$TMP/bm.json" <<JSON
[{"day":"2026-11-07","measured_at":"2026-11-07T07:00:00Z","weight_kg":74.2,"body_fat_percent":18.5,"lean_mass_estimated":false}]
JSON
send_code "$P1" POST 'body_metrics?on_conflict=user_id,day' "$TMP/bm.json"   -H "Prefer: resolution=merge-duplicates" > "$TMP/c3" 2>/dev/null || true
check "上傳體重" 201 "$(cat "$TMP/c3")"
check "家人看得到體重" 1 "$(count_rows "$TB" 'body_metrics?select=day')"
check "外人看不到體重" 0 "$(count_rows "$TC" 'body_metrics?select=day')"

echo "13 其餘的表也不給硬刪除"
for t in daily_checks body_metrics phases extra_burns body_profiles; do
  check "$t 的 DELETE 被擋" 403     "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H "apikey: $PUB"         -H "Authorization: Bearer $P1" "$BASE/rest/v1/$t?user_id=not.is.null")"
done

echo
echo "通過 $PASS 項，失敗 $FAIL 項"
[ "$FAIL" = "0" ]
