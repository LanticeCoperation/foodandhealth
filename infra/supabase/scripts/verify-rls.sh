#!/bin/sh
#
# 驗證 0001 的 RLS 真的把人隔開了。可重複執行，搬到 NAS 之後也該再跑一次。
#
#   sh scripts/verify-rls.sh
#
# 會建三個測試帳號（a、b 同一家庭，c 在外面），跑完自動刪掉。
# 用 PostgREST 的 Prefer: count=exact 讀 content-range 來數列數，不需要 jq。

set -e
cd "$(dirname "$0")/.."

env_get() { grep "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r"'"'"; }
PUB=$(env_get SUPABASE_PUBLISHABLE_KEY)
BASE=$(env_get SUPABASE_PUBLIC_URL)
[ -n "$BASE" ] || BASE="http://localhost:8000"

FAMILY="RLS驗證家-$$"
PW="verify-$(openssl rand -hex 8)"
A="rlsverify-a-$$@example.com"
B="rlsverify-b-$$@example.com"
C="rlsverify-c-$$@example.com"

PASS=0
FAIL=0
check() { # check <說明> <預期> <實際>
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s （預期 %s，實得 %s）\n' "$1" "$2" "$3"
  fi
}

cleanup() {
  sh scripts/admin.sh delete-user "$A" >/dev/null 2>&1 || true
  sh scripts/admin.sh delete-user "$B" >/dev/null 2>&1 || true
  sh scripts/admin.sh delete-user "$C" >/dev/null 2>&1 || true
  docker compose exec -T db psql -U postgres -d postgres -qtAc \
    "delete from public.families where name = '$FAMILY'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

login() { # login <email> -> access_token
  curl -s -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $PUB" -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\",\"password\":\"$PW\"}" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

# 回傳 PostgREST 的總列數（content-range 的分母）
count_rows() { # count_rows <token> <path>
  curl -s -D - -o /dev/null -H "apikey: $PUB" -H "Authorization: Bearer $1" \
       -H "Prefer: count=exact" "$BASE/rest/v1/$2" \
    | tr -d '\r' | sed -n 's|^[Cc]ontent-[Rr]ange: .*/||p'
}

status() { # status <token> <method> <path> [body]
  if [ -n "$4" ]; then
    curl -s -o /dev/null -w '%{http_code}' -X "$2" -H "apikey: $PUB" \
      -H "Authorization: Bearer $1" -H "Content-Type: application/json" \
      -d "$4" "$BASE/rest/v1/$3"
  else
    curl -s -o /dev/null -w '%{http_code}' -X "$2" -H "apikey: $PUB" \
      -H "Authorization: Bearer $1" "$BASE/rest/v1/$3"
  fi
}

echo "建立測試資料…"
sh scripts/admin.sh create-user "$A" FamA "$PW" >/dev/null
sh scripts/admin.sh create-user "$B" FamB "$PW" >/dev/null
sh scripts/admin.sh create-user "$C" Outsider "$PW" >/dev/null
sh scripts/admin.sh create-family "$FAMILY" >/dev/null
sh scripts/admin.sh add-member "$FAMILY" "$A" owner >/dev/null
sh scripts/admin.sh add-member "$FAMILY" "$B" >/dev/null

TA=$(login "$A"); TB=$(login "$B"); TC=$(login "$C")
[ -n "$TA" ] && [ -n "$TB" ] && [ -n "$TC" ] || { echo "登入失敗，停止" >&2; exit 1; }

echo "profiles"
check "甲看得到自己和乙，看不到丙"        2 "$(count_rows "$TA" 'profiles?select=user_id')"
check "乙同上"                            2 "$(count_rows "$TB" 'profiles?select=user_id')"
check "丙只看得到自己"                    1 "$(count_rows "$TC" 'profiles?select=user_id')"
check "沒帶 token（anon）讀不到"          401 "$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $PUB" "$BASE/rest/v1/profiles?select=user_id")"

echo "families / family_members"
check "甲看得到自己的家庭"                1 "$(count_rows "$TA" 'families?select=id')"
check "丙看不到別人的家庭"                0 "$(count_rows "$TC" 'families?select=id')"
check "甲看得到兩筆成員"                  2 "$(count_rows "$TA" 'family_members?select=user_id')"
check "丙看不到成員"                      0 "$(count_rows "$TC" 'family_members?select=user_id')"

echo "寫入"
# 403 = 有登入但沒有該表的 INSERT 權限（0001 只給了 select/update）
check "丙不能自己塞進家庭" 403 "$(status "$TC" POST 'family_members' "{\"family_id\":\"00000000-0000-0000-0000-000000000000\",\"user_id\":\"00000000-0000-0000-0000-000000000000\"}")"

UID_B=$(docker compose exec -T db psql -U postgres -d postgres -qtAc \
  "select id from auth.users where email = '$B'" | tr -d '\r\n ')
# 甲看得到乙的 profile，但 update policy 的 using 會把它濾掉 → 回傳空陣列
check "甲改乙的顯示名稱會影響 0 列" "[]" "$(curl -s -X PATCH \
  -H "apikey: $PUB" -H "Authorization: Bearer $TA" -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"display_name":"HACKED"}' "$BASE/rest/v1/profiles?user_id=eq.$UID_B")"
check "B 的名字沒被改掉" "FamB" "$(docker compose exec -T db psql -U postgres -d postgres -qtAc \
  "select display_name from public.profiles where user_id = '$UID_B'" | tr -d '\r\n ')"
# 自己的則改得動
check "甲改得動自己的顯示名稱" "204" "$(status "$TA" PATCH "profiles?user_id=eq.$(docker compose exec -T db psql -U postgres -d postgres -qtAc "select id from auth.users where email = '$A'" | tr -d '\r\n ')" '{"display_name":"FamA2"}')"

echo "輔助函式不該外露"
check "my_family_user_ids 不是 RPC 端點" 404 "$(status "$TA" POST 'rpc/my_family_user_ids' '{}')"
check "my_family_ids 不是 RPC 端點"      404 "$(status "$TA" POST 'rpc/my_family_ids' '{}')"

echo "全域檢查（新表漏開 RLS 會在這裡爆）"
check "public 底下沒有未啟用 RLS 的表" 0 "$(docker compose exec -T db psql -U postgres -d postgres -qtAc   "select count(*) from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity" | tr -d '
 ')"

for t in $(docker compose exec -T db psql -U postgres -d postgres -qtAc     "select relname from pg_class where relnamespace='public'::regnamespace and relkind='r' order by relname" | tr -d ''); do
  [ -n "$t" ] || continue
  check "anon 讀不到 $t" 401 "$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $PUB" "$BASE/rest/v1/$t?select=*&limit=1")"
done

echo
echo "通過 $PASS 項，失敗 $FAIL 項"
[ "$FAIL" = "0" ]
