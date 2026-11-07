-- 0001_identity.sql
--
-- 身分與家庭群組。資料表（飲食、體重……）在 0002 之後，跟 drift schema 12 一起設計。
--
-- 不開放對外註冊：帳號一律由管理端用 service_role 建立（見 scripts/admin-create-user.sh）。
-- 因此這裡沒有 join_family 之類讓使用者自助加入的 RPC，
-- 也沒有 auth.users 的觸發器（postgres 不是 superuser，auth schema 屬於 supabase_admin）。
--
-- 套用：
--   docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < migrations/0001_identity.sql

begin;

-- ---------------------------------------------------------------------------
-- private schema：放 RLS policy 要用的輔助函式。
--
-- 不能放 public：public 的 default privileges 會自動把 EXECUTE 給 anon，
-- 而且 PGRST_DB_SCHEMAS=public,graphql_public 會把它變成 /rest/v1/rpc/... 端點。
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- 資料表
-- ---------------------------------------------------------------------------

-- 顯示名稱。auth.users 不開放給 authenticated 直接讀，
-- 家人之間要看得到彼此是誰，就得在 public 自己存一份。
create table public.profiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.families (
  id         uuid primary key default gen_random_uuid(),
  -- unique：管理腳本用名稱找家庭，同名會讓 add-member 無法分辨
  name       text not null unique check (char_length(name) between 1 and 40),
  -- 可為 null：刪掉建立者的帳號時不該讓整個 family 跟著消失，也不該擋住帳號刪除
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

-- policy 會用 user_id 反查，主鍵是 (family_id, user_id) 所以要另外補這個索引
create index family_members_user_id_idx on public.family_members (user_id);

-- ---------------------------------------------------------------------------
-- 權限
--
-- public schema 的 default privileges 會自動把 ALL 給 anon 和 authenticated，
-- 所以新表預設是全開的，擋住它的只有 RLS。這裡把 anon 整個收掉當第二道防線：
-- 就算之後有人漏寫 policy，沒登入的人也碰不到。
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.families, public.family_members from anon;

revoke all on public.profiles, public.families, public.family_members from authenticated;
-- 只開 display_name 一欄，避免使用者連 created_at 都能改
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant select on public.families to authenticated;
grant select on public.family_members to authenticated;

-- ---------------------------------------------------------------------------
-- 輔助函式
--
-- 必須 security definer：policy 若直接查 family_members，而 family_members 自己
-- 的 policy 又要查 family_members，會無限遞迴。definer 以 owner 身分執行、
-- owner 不受 RLS 限制，遞迴就斷掉了。
-- search_path 鎖成空字串，所有名稱寫全，避免被 search_path 劫持。
-- ---------------------------------------------------------------------------

create function private.my_family_ids()
  returns setof uuid
  language sql
  security definer
  stable
  set search_path = ''
as $$
  select fm.family_id
  from public.family_members fm
  where fm.user_id = (select auth.uid())
$$;

-- 跟我同家庭的所有人（含自己）
create function private.my_family_user_ids()
  returns setof uuid
  language sql
  security definer
  stable
  set search_path = ''
as $$
  select fm.user_id
  from public.family_members fm
  where fm.family_id in (
    select mine.family_id
    from public.family_members mine
    where mine.user_id = (select auth.uid())
  )
$$;

revoke all on function private.my_family_ids() from public;
revoke all on function private.my_family_user_ids() from public;
grant execute on function private.my_family_ids() to authenticated;
grant execute on function private.my_family_user_ids() to authenticated;

create function private.touch_updated_at()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
--
-- 每一張表都必須開。anon key 會被打包進 .ipa / .apk，
-- 沒開 RLS 的表等於對所有拿得到那把 key 的人開放。
-- ---------------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.families       enable row level security;
alter table public.family_members enable row level security;

-- 自己的，或同家庭成員的
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or user_id in (select private.my_family_user_ids())
  );

-- 只能改自己的顯示名稱；不能新增或刪除（帳號由管理端建立時一併建 profile）
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy families_select on public.families
  for select to authenticated
  using (id in (select private.my_family_ids()));

create policy family_members_select on public.family_members
  for select to authenticated
  using (family_id in (select private.my_family_ids()));

-- 刻意不給 families / family_members 任何 insert / update / delete policy。
-- 群組成員的異動一律由管理端（service_role，bypassrls）處理。

-- PostgREST 有 schema cache，不通知的話新表會一直回 PGRST205
notify pgrst, 'reload schema';

commit;
