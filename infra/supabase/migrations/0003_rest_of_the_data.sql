-- 0003_rest_of_the_data.sql
--
-- 其餘的資料表。它們不是同一種東西，同步規則也不一樣：
--
--   A 健康資料快取（body_metrics、daily_activity）
--     正本在 Apple 健康 / Health Connect。**只上傳，不下拉回本機表**——
--     下拉的列會被下一次健康資料整理覆蓋，而且 fromThisApp 可能跟著跑到
--     沒寫過它的裝置上，那台就會以為自己刪得掉 Apple 健康裡的紀錄。
--     放在伺服器上只為了家人看得到。
--
--   B 自然鍵的使用者資料（daily_checks、body_profiles）
--     雙向同步，以 (user_id, day, item) / (user_id) 為鍵 upsert。
--
--   C 自動編號的使用者資料（phases、extra_burns）
--     跟 food_entries 一樣，用裝置產的 sync_id。
--
-- 套用：
--   docker compose exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 < migrations/0003_rest_of_the_data.sql

begin;

-- ---------------------------------------------------------------------------
-- A 健康資料快取（只上傳）
-- ---------------------------------------------------------------------------

create table public.body_metrics (
  user_id             uuid not null default auth.uid()
                        references auth.users(id) on delete cascade,
  day                 text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  measured_at         timestamptz not null,
  weight_kg           double precision not null,
  body_fat_percent    double precision,
  lean_mass_kg        double precision,
  lean_mass_estimated boolean not null default false,
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  primary key (user_id, day)
);

create table public.daily_activity (
  user_id     uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  day         text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  active_kcal double precision not null,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  primary key (user_id, day)
);

-- ---------------------------------------------------------------------------
-- B 自然鍵的使用者資料（雙向）
-- ---------------------------------------------------------------------------

create table public.daily_checks (
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  day        text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  item       text not null,
  checked_at timestamptz not null,
  amount     double precision,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, day, item)
);

-- 身體基本資料與 TDEE。
--
-- **刻意不併進 public.profiles**：那張是身分表，家人讀得到裡面的 display_name。
-- 性別、出生年、身高、TDEE 是另一回事，要能單獨決定給不給家人看。
-- 這裡的選擇是：給（家人本來就看得到彼此的體重與熱量）。
create table public.body_profiles (
  user_id     uuid primary key default auth.uid()
                references auth.users(id) on delete cascade,
  sex         text not null,
  birth_year  integer not null,
  height_cm   double precision not null,
  activity    text not null,
  weight_kg   double precision not null,
  tdee_kcal   double precision not null,
  energy_mode text not null,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- C 自動編號的使用者資料（裝置產 sync_id）
-- ---------------------------------------------------------------------------

create table public.phases (
  sync_id          uuid primary key,
  user_id          uuid not null default auth.uid()
                     references auth.users(id) on delete cascade,
  name             text not null check (char_length(name) between 1 and 60),
  start_day        text not null check (start_day ~ '^\d{4}-\d{2}-\d{2}$'),
  end_day          text not null check (end_day ~ '^\d{4}-\d{2}-\d{2}$'),
  hypothesis       text,
  target_kcal      double precision,
  target_protein_g double precision,
  creatine         boolean not null default false,
  conclusion       text,
  created_at       timestamptz not null,
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

create table public.extra_burns (
  sync_id    uuid primary key,
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  day        text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  kcal       double precision not null,
  note       text,
  created_at timestamptz not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- 索引：增量下拉的游標 + 家人頁依日期查
-- ---------------------------------------------------------------------------
create index body_metrics_user_updated_idx on public.body_metrics (user_id, updated_at);
create index daily_activity_user_updated_idx on public.daily_activity (user_id, updated_at);
create index daily_checks_user_updated_idx on public.daily_checks (user_id, updated_at);
create index phases_user_updated_idx on public.phases (user_id, updated_at);
create index extra_burns_user_updated_idx on public.extra_burns (user_id, updated_at);
create index extra_burns_user_day_idx on public.extra_burns (user_id, day);

-- ---------------------------------------------------------------------------
-- updated_at 一律由伺服器蓋掉（理由同 0002：手機時鐘不可信，而這是下拉游標）
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'body_metrics', 'daily_activity', 'daily_checks',
    'body_profiles', 'phases', 'extra_burns'
  ] loop
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function private.stamp_updated_at()',
      t || '_stamp_updated_at', t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 權限與 RLS
--
-- public schema 的 default privileges 會自動把 ALL 給 anon 和 authenticated，
-- 新表預設全開，唯一擋住的是 RLS。anon 整個收掉當第二道防線。
-- 不給 DELETE：刪除一律走 deleted_at 墓碑（body_profiles 沒有刪除的概念）。
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'body_metrics', 'daily_activity', 'daily_checks',
    'body_profiles', 'phases', 'extra_burns'
  ] loop
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke all on public.%I from authenticated', t);
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('alter table public.%I enable row level security', t);

    -- 自己的，或同家庭成員的
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (user_id = (select auth.uid()) '
      '       or user_id in (select private.my_family_user_ids()))',
      t || '_select', t
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (user_id = (select auth.uid()))',
      t || '_insert', t
    );
    -- using 擋「能改哪些列」，with check 擋「改完不能變成別人的」。兩個都要。
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (user_id = (select auth.uid())) '
      'with check (user_id = (select auth.uid()))',
      t || '_update', t
    );
  end loop;
end $$;

notify pgrst, 'reload schema';

commit;
