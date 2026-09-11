-- ============================================================
-- MonIQ — Household Cloud Sync schema
-- Run this once in Supabase: Project → SQL Editor → New Query → Run
-- ============================================================

-- Households
create table if not exists households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique not null,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- Membership: links a signed-in user to a household
create table if not exists household_members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid references households(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  display_name text not null,
  joined_at timestamptz default now(),
  unique(household_id, user_id)
);

-- Shared app data: one JSON blob per household (mirrors the app's local data shape)
create table if not exists app_data (
  household_id uuid primary key references households(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz default now()
);

-- ============================================================
-- Row Level Security — only household members can see/edit their household's data
-- ============================================================
alter table households enable row level security;
alter table household_members enable row level security;
alter table app_data enable row level security;

create or replace function is_household_member(hid uuid)
returns boolean language sql security definer as $$
  select exists(
    select 1 from household_members
    where household_id = hid and user_id = auth.uid()
  );
$$;

create policy "members can view their household" on households
  for select using (is_household_member(id));

create policy "members can view membership rows" on household_members
  for select using (is_household_member(household_id));

create policy "members can read shared data" on app_data
  for select using (is_household_member(household_id));

create policy "members can update shared data" on app_data
  for update using (is_household_member(household_id));

-- ============================================================
-- Functions used by the app to create/join a household safely
-- (these bypass RLS internally via SECURITY DEFINER, then apply their own checks)
-- ============================================================
create or replace function create_household(p_name text, p_display_name text)
returns table(household_id uuid, invite_code text)
language plpgsql security definer as $$
declare
  hid uuid;
  code text;
begin
  code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into households(name, invite_code, created_by)
    values (p_name, code, auth.uid()) returning id into hid;
  insert into household_members(household_id, user_id, display_name)
    values (hid, auth.uid(), p_display_name);
  insert into app_data(household_id, data) values (hid, '{}'::jsonb);
  return query select hid, code;
end;
$$;

create or replace function join_household_by_code(p_code text, p_display_name text)
returns uuid language plpgsql security definer as $$
declare
  hid uuid;
  member_count int;
begin
  select id into hid from households where invite_code = upper(p_code);
  if hid is null then
    raise exception 'Invalid invite code';
  end if;
  select count(*) into member_count from household_members where household_id = hid;
  -- Cap at 5 members per Sharing group. A user re-joining (already a member) is allowed through
  -- regardless of count, since the upsert below just updates their display name, not a new seat.
  if member_count >= 5 and not exists (
    select 1 from household_members where household_id = hid and user_id = auth.uid()
  ) then
    raise exception 'This Sharing group already has 5 members, which is the limit.';
  end if;
  insert into household_members(household_id, user_id, display_name)
    values (hid, auth.uid(), p_display_name)
    on conflict (household_id, user_id) do update set display_name = excluded.display_name;
  insert into app_data(household_id, data) values (hid, '{}'::jsonb)
    on conflict (household_id) do nothing;
  return hid;
end;
$$;

create or replace function leave_household(hid uuid)
returns void language plpgsql security definer as $$
begin
  delete from household_members where household_id = hid and user_id = auth.uid();
end;
$$;

-- ============================================================
-- Enable Realtime updates on app_data so household members see live changes
-- ============================================================
alter publication supabase_realtime add table app_data;

-- ============================================================
-- AI Chat usage tracking — server-enforced monthly cap for the bundled
-- "AI Insights" feature. Each authenticated user gets a fixed number of
-- included questions per calendar month; the ai-chat Edge Function calls
-- increment_ai_usage() to atomically check-and-increment, so the cap can't
-- be bypassed by a client that ignores what it's told.
-- ============================================================

create table if not exists ai_usage (
  user_id uuid references auth.users(id) on delete cascade,
  month text not null,               -- 'YYYY-MM', e.g. '2026-09'
  question_count int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, month)
);

alter table ai_usage enable row level security;

create policy "Users can read their own AI usage"
  on ai_usage for select
  using (auth.uid() = user_id);

-- No insert/update/delete policies for regular users — all writes happen
-- through increment_ai_usage() below, which runs as security definer and
-- bypasses RLS deliberately, so a client can't forge a lower usage count.

-- p_limit is passed in from the Edge Function (not hardcoded here) so the
-- monthly cap can be changed in one place — the Edge Function's config —
-- without a schema migration.
create or replace function increment_ai_usage(p_limit int)
returns table(allowed boolean, current_count int, limit_count int)
language plpgsql security definer as $$
declare
  cur_month text := to_char(now(), 'YYYY-MM');
  existing int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into ai_usage(user_id, month, question_count)
    values (auth.uid(), cur_month, 0)
    on conflict (user_id, month) do nothing;

  select question_count into existing
    from ai_usage where user_id = auth.uid() and month = cur_month
    for update;

  if existing >= p_limit then
    return query select false, existing, p_limit;
    return;
  end if;

  update ai_usage set question_count = existing + 1, updated_at = now()
    where user_id = auth.uid() and month = cur_month;

  return query select true, existing + 1, p_limit;
end;
$$;
