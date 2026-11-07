#!/bin/sh
#
# Body Lab 自架 Supabase 的管理工具。
#
# 對外註冊是關掉的（.env 的 DISABLE_SIGNUP=true），所有帳號都從這裡建。
# 用 service_role 金鑰呼叫 auth 的 admin API，再用 psql 寫 profile 與家庭成員。
# 刻意不依賴 jq / node，NAS 上也能直接跑。
#
# 用法：
#   sh scripts/admin.sh create-user <email> [display_name] [password]
#   sh scripts/admin.sh set-password <email> [password]
#   sh scripts/admin.sh delete-user <email>
#   sh scripts/admin.sh create-family <name>
#   sh scripts/admin.sh add-member <family_name> <email> [owner|member]
#   sh scripts/admin.sh remove-member <family_name> <email>
#   sh scripts/admin.sh list
#
# password 省略時自動產生並印出來一次，轉達給家人後就不會再顯示。

set -e
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "找不到 .env，請先完成 infra/README.md 的設定" >&2; exit 1; }

env_get() { grep "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '\r"'"'"; }

SECRET=$(env_get SUPABASE_SECRET_KEY)
BASE=$(env_get SUPABASE_PUBLIC_URL)
[ -n "$SECRET" ] || { echo ".env 裡沒有 SUPABASE_SECRET_KEY" >&2; exit 1; }
[ -n "$BASE" ] || BASE="http://localhost:8000"

psql_do() { docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }

# SQL 字面值跳脫：單引號變兩個單引號
sqlq() { printf "%s" "$1" | sed "s/'/''/g"; }

# JSON 字串跳脫：反斜線與雙引號
jsonq() { printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

uid_of() {
  psql_do -tAc "select id from auth.users where email = '$(sqlq "$1")'"
}

gen_password() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-16; }

require() {
  [ -n "$2" ] || { echo "缺少參數：$1" >&2; echo "用法見 scripts/admin.sh 檔頭" >&2; exit 1; }
}

CMD="${1:-}"
[ $# -gt 0 ] && shift

case "$CMD" in

  create-user)
    EMAIL="$1"; NAME="${2:-}"; PW="${3:-}"
    require email "$EMAIL"
    [ -n "$NAME" ] || NAME=$(printf "%s" "$EMAIL" | cut -d@ -f1)
    GENERATED=0
    if [ -z "$PW" ]; then PW=$(gen_password); GENERATED=1; fi

    if [ -n "$(uid_of "$EMAIL")" ]; then
      echo "帳號已存在：$EMAIL（要改密碼請用 set-password）" >&2
      exit 1
    fi

    CODE=$(curl -s -o /tmp/admin_resp.$$ -w '%{http_code}' -X POST "$BASE/auth/v1/admin/users" \
      -H "apikey: $SECRET" -H "Authorization: Bearer $SECRET" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$(jsonq "$EMAIL")\",\"password\":\"$(jsonq "$PW")\",\"email_confirm\":true}")
    if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
      echo "建立帳號失敗（HTTP $CODE）：" >&2; head -c 400 /tmp/admin_resp.$$ >&2; echo >&2
      rm -f /tmp/admin_resp.$$; exit 1
    fi
    rm -f /tmp/admin_resp.$$

    psql_do -q -c "insert into public.profiles (user_id, display_name)
                   select id, '$(sqlq "$NAME")' from auth.users where email = '$(sqlq "$EMAIL")'
                   on conflict (user_id) do update set display_name = excluded.display_name"

    echo "已建立 $EMAIL（顯示名稱：$NAME）"
    if [ "$GENERATED" = "1" ]; then echo "密碼（只會顯示這一次）：$PW"; fi
    ;;

  set-password)
    EMAIL="$1"; PW="${2:-}"
    require email "$EMAIL"
    UID_=$(uid_of "$EMAIL")
    [ -n "$UID_" ] || { echo "查無帳號：$EMAIL" >&2; exit 1; }
    GENERATED=0
    if [ -z "$PW" ]; then PW=$(gen_password); GENERATED=1; fi

    CODE=$(curl -s -o /tmp/admin_resp.$$ -w '%{http_code}' -X PUT "$BASE/auth/v1/admin/users/$UID_" \
      -H "apikey: $SECRET" -H "Authorization: Bearer $SECRET" \
      -H "Content-Type: application/json" \
      -d "{\"password\":\"$(jsonq "$PW")\"}")
    if [ "$CODE" != "200" ]; then
      echo "改密碼失敗（HTTP $CODE）：" >&2; head -c 400 /tmp/admin_resp.$$ >&2; echo >&2
      rm -f /tmp/admin_resp.$$; exit 1
    fi
    rm -f /tmp/admin_resp.$$
    echo "已更新 $EMAIL 的密碼"
    if [ "$GENERATED" = "1" ]; then echo "新密碼（只會顯示這一次）：$PW"; fi
    ;;

  delete-user)
    EMAIL="$1"
    require email "$EMAIL"
    UID_=$(uid_of "$EMAIL")
    [ -n "$UID_" ] || { echo "查無帳號：$EMAIL" >&2; exit 1; }
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/auth/v1/admin/users/$UID_" \
      -H "apikey: $SECRET" -H "Authorization: Bearer $SECRET")
    [ "$CODE" = "200" ] || { echo "刪除失敗（HTTP $CODE）" >&2; exit 1; }
    echo "已刪除 $EMAIL（profile 與家庭成員資格會連帶刪除）"
    ;;

  create-family)
    NAME="$1"
    require name "$NAME"
    psql_do -qtAc "insert into public.families (name) values ('$(sqlq "$NAME")') returning id" \
      | while read -r id; do [ -n "$id" ] && echo "已建立家庭「$NAME」：$id"; done
    ;;

  add-member)
    FAMILY="$1"; EMAIL="$2"; ROLE="${3:-member}"
    require family_name "$FAMILY"; require email "$EMAIL"
    N=$(psql_do -qtAc "with x as (
                   insert into public.family_members (family_id, user_id, role)
                   select f.id, u.id, '$(sqlq "$ROLE")'
                   from public.families f, auth.users u
                   where f.name = '$(sqlq "$FAMILY")' and u.email = '$(sqlq "$EMAIL")'
                   on conflict (family_id, user_id) do update set role = excluded.role
                   returning 1) select count(*) from x" | tr -d '
 ')
    [ "$N" = "0" ] && { echo "查無家庭「$FAMILY」或帳號 $EMAIL，沒有異動" >&2; exit 1; }
    echo "已把 $EMAIL 加入「$FAMILY」（$ROLE）"
    ;;

  remove-member)
    FAMILY="$1"; EMAIL="$2"
    require family_name "$FAMILY"; require email "$EMAIL"
    N=$(psql_do -qtAc "with x as (
                   delete from public.family_members fm
                   using public.families f, auth.users u
                   where fm.family_id = f.id and fm.user_id = u.id
                     and f.name = '$(sqlq "$FAMILY")' and u.email = '$(sqlq "$EMAIL")'
                   returning 1) select count(*) from x" | tr -d '
 ')
    [ "$N" = "0" ] && { echo "查無家庭「$FAMILY」或該成員，沒有異動" >&2; exit 1; }
    echo "已把 $EMAIL 移出「$FAMILY」"
    ;;

  list)
    echo "--- 帳號 ---"
    psql_do -c "select u.email, p.display_name, u.created_at::date as 建立日
                from auth.users u left join public.profiles p on p.user_id = u.id
                order by u.created_at"
    echo "--- 家庭成員 ---"
    psql_do -c "select f.name as 家庭, u.email, fm.role
                from public.family_members fm
                join public.families f on f.id = fm.family_id
                join auth.users u on u.id = fm.user_id
                order by f.name, fm.role desc, u.email"
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
