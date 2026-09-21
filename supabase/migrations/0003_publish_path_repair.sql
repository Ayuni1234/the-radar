-- ============================================================
-- Migration 0003 — Publish-path repair (ONE-SHOT: run once)
--
-- Diagnosis: the production `feed_posts` table was bootstrapped from an
-- older schema (author_id / post_kind / area_label / author_avatar /
-- is_minor / likes_count) while the canonical `supabase/schema.sql` uses
-- (author_profile_id / kind / area_name / media_platform ...). Every
-- client publish therefore failed with `column ... does not exist`, which
-- the app mislabeled as an offline outage ("Could not publish — queued
-- for sync"). The INSERT policy also referenced author_id.
--
-- This migration rebuilds `feed_posts` in the canonical shape while
-- preserving existing rows (unresolvable authors are parked in
-- `feed_posts_legacy_backup`), creates the missing
-- `public.stream_bounties` table (+ lifecycle trigger and poster-only
-- `release_bounty` RPC), and reinstalls the canonical RLS policies.
-- ============================================================

-- ------------------------------------------------------------
-- 1. feed_posts → canonical shape (data-preserving rebuild)
-- ------------------------------------------------------------
create table if not exists public.feed_posts_legacy_backup as
  select * from public.feed_posts;

insert into public.feed_posts_legacy_backup
select * from public.feed_posts
where not exists (
  select 1 from public.feed_posts_legacy_backup b where b.id = public.feed_posts.id
);

drop table if exists public.feed_posts cascade;

create table public.feed_posts (
  id uuid primary key default gen_random_uuid(),
  author_profile_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  author_role text not null default 'player',
  kind text not null default 'highlight' check (kind in ('highlight','drill','tactical','general')),
  body text not null,
  media_url text,
  media_platform text,
  media_kind text check (media_kind in ('link','device_video','device_photo')),
  media_duration_s integer check (media_duration_s is null or media_duration_s <= 180),
  area_name text,
  latitude double precision,
  longitude double precision,
  is_minor_poster boolean not null default false,
  created_at timestamptz not null default now()
);

-- Copy legacy rows whose author resolves to a real profile (legacy
-- author_id referenced auth.users). Anything unresolvable stays parked
-- in feed_posts_legacy_backup — it never blocks the migration.
insert into public.feed_posts
      (id, author_profile_id, author_name, author_role, kind, body,
       media_url, area_name, latitude, longitude, is_minor_poster, created_at)
select b.id,
       b.author_id,
       b.author_name,
       b.author_role,
       b.post_kind,
       b.body,
       b.media_url,
       b.area_label,
       b.latitude,
       b.longitude,
       b.is_minor,
       b.created_at
  from public.feed_posts_legacy_backup b
 where exists (select 1 from public.profiles p where p.id = b.author_id)
   and not exists (select 1 from public.feed_posts n where n.id = b.id);

-- Privacy trigger (mirrors profile minor state; fences minor posts).
create or replace function public.enforce_feed_post_privacy()
returns trigger as $$
declare
  poster_is_minor boolean := false;
  poster_area text;
begin
  select p.is_minor,
         coalesce(nullif(btrim(coalesce(p.geohash_area, '')), ''),
                  nullif(btrim(coalesce(p.city, '')), ''), 'Region withheld')
    into poster_is_minor, poster_area
  from public.profiles p where p.id = new.author_profile_id;

  new.is_minor_poster := coalesce(poster_is_minor, false);
  if new.is_minor_poster then
    new.area_name := poster_area;      -- coarse regional label only
    new.latitude := null;              -- no coordinates leave the DB
    new.longitude := null;
    new.media_url := null;             -- no external media for minors
    new.media_platform := null;
  end if;
  return new;
end;
$$ language plpgsql;
drop trigger if exists feed_posts_privacy on public.feed_posts;
create trigger feed_posts_privacy
  before insert or update on public.feed_posts
  for each row execute function public.enforce_feed_post_privacy();

-- Canonical RLS policies.
alter table public.feed_posts enable row level security;
drop policy if exists "feed posts are readable" on public.feed_posts;
create policy "feed posts are readable" on public.feed_posts
  for select using (true);
drop policy if exists "Authenticated users can create feed posts"
  on public.feed_posts;
drop policy if exists "Authors can delete their own feed posts"
  on public.feed_posts;
drop policy if exists "authors manage own posts" on public.feed_posts;
create policy "authors manage own posts" on public.feed_posts
  for all using (author_profile_id = auth.uid());

alter publication supabase_realtime add table public.feed_posts;

-- ------------------------------------------------------------
-- 2. stream_bounties — missing in production
-- ------------------------------------------------------------
create table if not exists public.stream_bounties (
  id uuid primary key default gen_random_uuid(),
  poster_profile_id uuid not null references public.profiles(id) on delete cascade,
  poster_name text not null,
  title text not null,
  brief text not null,
  area_name text not null,
  venue_name text,
  latitude double precision,
  longitude double precision,
  amount_pi double precision not null check (amount_pi >= 5),
  duration_minutes int not null default 90 check (duration_minutes between 15 and 240),
  kickoff_at timestamptz,
  -- open | funded | accepted | live | completed | cancelled | disputed
  status text not null default 'open',
  streamer_profile_id uuid references public.profiles(id) on delete set null,
  streamer_name text,
  stream_url text,
  watched_minutes int not null default 0,
  funded_payment_id text,
  released_payment_id text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.stream_bounties enable row level security;
drop policy if exists "bounties are readable" on public.stream_bounties;
create policy "bounties are readable" on public.stream_bounties
  for select using (true);
drop policy if exists "posters manage own bounties" on public.stream_bounties;
create policy "posters manage own bounties" on public.stream_bounties
  for all using (poster_profile_id = auth.uid());
drop policy if exists "streamers update assigned bounties"
  on public.stream_bounties;
create policy "streamers update assigned bounties" on public.stream_bounties
  for update using (
    streamer_profile_id = auth.uid()
    or (status = 'funded' and streamer_profile_id is null)
  );

-- State machine guard: only the poster releases/cancels; the assigned
-- streamer may only advance accepted -> live -> completed.
create or replace function public.enforce_bounty_lifecycle()
returns trigger as $$
begin
  if new.poster_profile_id is distinct from old.poster_profile_id
     or new.amount_pi is distinct from old.amount_pi then
    raise exception 'bounty poster and amount are immutable';
  end if;
  if old.status in ('completed','cancelled') then
    raise exception 'bounty is closed';
  end if;
  if new.status is distinct from old.status then
    if not (
      (old.status = 'open' and new.status in ('funded','cancelled'))
      or (old.status = 'funded' and new.status in ('accepted','cancelled'))
      or (old.status = 'accepted' and new.status in ('live','disputed'))
      or (old.status = 'live' and new.status in ('completed','disputed'))
      or (old.status = 'disputed' and new.status in ('completed','cancelled'))
    ) then
      raise exception 'illegal bounty transition % -> %', old.status, new.status;
    end if;
    new.updated_at := now();
  end if;
  return new;
end;
$$ language plpgsql;
drop trigger if exists stream_bounties_lifecycle on public.stream_bounties;
create trigger stream_bounties_lifecycle
  before update on public.stream_bounties
  for each row execute function public.enforce_bounty_lifecycle();

-- Poster-only release RPC (SECURITY DEFINER).
create or replace function public.release_bounty(bounty_id uuid)
returns void as $$
declare
  b public.stream_bounties%rowtype;
  me uuid := auth.uid();
begin
  select * into b from public.stream_bounties where id = bounty_id;
  if b.id is null then
    raise exception 'bounty not found';
  end if;
  if b.poster_profile_id is distinct from me then
    raise exception 'only the bounty poster can release the escrow';
  end if;
  if b.status not in ('live','disputed') then
    raise exception 'bounty is not in a releasable state';
  end if;
  update public.stream_bounties
     set status = 'completed',
         completed_at = now(),
         updated_at = now()
   where id = bounty_id;
end;
$$ language plpgsql security definer;
grant execute on function public.release_bounty(uuid) to authenticated;

alter publication supabase_realtime add table public.stream_bounties;
