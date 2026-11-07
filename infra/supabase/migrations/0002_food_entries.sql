-- 0002_food_entries.sql
--
-- 第一張真的會同步的資料表，對應 drift 的 FoodEntries。
-- 設計上的決定寫在下面，drift schema 12 要跟著對齊。
--
-- 套用：
--   docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < migrations/0002_food_entries.sql

begin;

create table public.food_entries (
  -- 主鍵是裝置產生的 UUID，不是本機的 autoIncrement id。
  -- 兩支手機各自長號碼必定相撞，所以同步用的身分必須由裝置產且全域唯一。
  sync_id    uuid primary key,

  -- 用戶端不送這欄，由 auth.uid() 填。insert policy 也會再擋一次。
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,

  eaten_at   timestamptz not null,
  meal       text not null check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  name       text not null check (char_length(name) between 1 and 100),
  servings   double precision not null default 1,
  kcal       double precision,
  protein_g  double precision,
  carbs_g    double precision,
  fat_g      double precision,
  note       text,

  -- 使用者的真實資料（哪時候記的），用上傳的值，不要 default now()
  created_at timestamptz not null,

  -- 伺服器說了算，見下面的觸發器。這是增量下拉的游標。
  updated_at timestamptz not null default now(),

  -- 墓碑。刪除是 update deleted_at，不是真的 delete，
  -- 否則另一台永遠不知道這筆被刪了。
  deleted_at timestamptz
);

-- 增量下拉：where user_id = ... and updated_at >= 游標
create index food_entries_user_updated_idx on public.food_entries (user_id, updated_at);
-- 日常查詢：某人某段期間吃了什麼
create index food_entries_user_eaten_idx on public.food_entries (user_id, eaten_at);

-- ---------------------------------------------------------------------------
-- updated_at 一律由伺服器蓋掉
--
-- 手機的時鐘不可信（時區、使用者自己改、離線很久才上傳）。
-- 這欄是下拉游標，被一支時鐘快的手機寫進未來值，其他台就會漏資料。
-- ---------------------------------------------------------------------------
create function private.stamp_updated_at()
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

create trigger food_entries_stamp_updated_at
  before insert or update on public.food_entries
  for each row execute function private.stamp_updated_at();

-- ---------------------------------------------------------------------------
-- 權限
-- ---------------------------------------------------------------------------
revoke all on public.food_entries from anon;
revoke all on public.food_entries from authenticated;
-- 沒有 delete：刪除走 deleted_at
grant select, insert, update on public.food_entries to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.food_entries enable row level security;

-- 自己的，或同家庭成員的（家人唯讀靠下面沒有給他們 update policy 來達成）
create policy food_entries_select on public.food_entries
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or user_id in (select private.my_family_user_ids())
  );

create policy food_entries_insert on public.food_entries
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- using 擋「能改哪些列」，with check 擋「改完不能變成別人的」。兩個都要。
create policy food_entries_update on public.food_entries
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 給 Flutter 端的提醒
--
-- 1. 上傳用 upsert：
--      POST /rest/v1/food_entries?on_conflict=sync_id
--      Prefer: resolution=merge-duplicates
--    重送同一批 sync_id 不會產生重複列，所以網路不穩重試是安全的。
--
-- 2. 下拉游標要往回抓幾秒：
--      updated_at >= 上次游標 - 5 秒
--    now() 取的是交易開始時間，一筆交易可能在游標讀過之後才 commit，
--    完全等於游標會漏掉它。多抓的部分用 sync_id 去重。
-- ---------------------------------------------------------------------------

notify pgrst, 'reload schema';

commit;
