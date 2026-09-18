-- ============================================================
-- The Radar — Global Football Scouting Platform
-- Supabase schema (run in the Supabase SQL editor)
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- profiles: players, verified scouts, clubs, academies, agents, parents
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id                uuid primary key default gen_random_uuid(),
  pi_uid            text unique not null,           -- app-scoped Pi identifier
  username          text not null,
  role              text not null default 'player'
                    check (role in ('player','scout','club','academy','agent','parent')),
  credibility_score numeric(5,2) not null default 0,
  kyc_verified      boolean not null default false,
  display_name      text,
  bio               text,
  country           text,
  city              text,
  positions         text[] not null default '{}',
  football_cv       text,
  video_showcase_urls text[] not null default '{}',
  club_affiliation  text,
  is_minor          boolean not null default false,
  geohash_area      text,                            -- coarse area label (minors: only this)
  rating            numeric(3,2) not null default 0,
  avatar_url        text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ------------------------------------------------------------
-- radar_events: live training sessions, matches, trials, tournaments
-- ------------------------------------------------------------
create table if not exists public.radar_events (
  id                uuid primary key default gen_random_uuid(),
  event_type        text not null
                    check (event_type in ('trainingSession','match','trial','tournament')),
  title             text not null,
  host_profile_id   uuid references public.profiles(id) on delete cascade,
  host_name         text not null,
  latitude          double precision not null,
  longitude         double precision not null,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  geo_precision     text not null default 'approximate'
                    check (geo_precision in ('exact','approximate')),
  venue_name        text,            -- only rendered when geo_precision = 'exact'
  area_name         text,            -- coarse human label, always rendered
  description       text,
  capacity          integer,
  attending_count   integer not null default 0,
  min_age           integer,
  max_age           integer,
  is_minor_protected boolean not null default false,
  boosted_until     timestamptz,
  bounty_pi         numeric(12,7),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists radar_events_starts_idx on public.radar_events (starts_at);
create index if not exists radar_events_type_idx  on public.radar_events (event_type);

-- ------------------------------------------------------------
-- pi_payments: mirror of Pi Platform payments (webhook-maintained)
-- ------------------------------------------------------------
create table if not exists public.pi_payments (
  identifier      text primary key,          -- Pi payment id
  user_uid        text not null,             -- payer's Pi uid
  amount          numeric(12,7) not null,
  memo            text not null,
  product         text,                      -- premium_search_30d | session_boost_48h | scouting_bounty
  metadata        jsonb not null default '{}',
  status          text not null default 'created'
                  check (status in ('created','approved','completed','cancelled','error')),
  txid            text,
  network         text,
  created_at      timestamptz not null default now(),
  completed_at    timestamptz
);
create index if not exists pi_payments_user_idx on public.pi_payments (user_uid);

-- ------------------------------------------------------------
-- grants: entitlements unlocked by completed payments
-- ------------------------------------------------------------
create table if not exists public.entitlements (
  id           uuid primary key default gen_random_uuid(),
  user_uid     text not null,
  product      text not null,
  reference_id text,                          -- e.g. boosted event id
  granted_at   timestamptz not null default now(),
  expires_at   timestamptz
);
create index if not exists entitlements_user_idx on public.entitlements (user_uid);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.radar_events enable row level security;
alter table public.pi_payments  enable row level security;
alter table public.entitlements enable row level security;

-- Public read of profiles, but minors' exact locations are never stored
-- client-side anyway; geohash_area is the only location column exposed.
create policy "profiles are readable" on public.profiles
  for select using (true);
create policy "users update own profile" on public.profiles
  for update using (auth.jwt() ->> 'sub' = pi_uid);
create policy "users insert own profile" on public.profiles
  for insert with check (auth.jwt() ->> 'sub' = pi_uid);

-- Events are publicly readable (approximate data for minor-protected rows).
create policy "events are readable" on public.radar_events
  for select using (true);
create policy "hosts manage own events" on public.radar_events
  for all using (auth.jwt() ->> 'sub' = host_profile_id::text);

-- Payments/entitlements: service role (edge functions) only.
create policy "payments service only" on public.pi_payments
  for select using (false);
create policy "entitlements readable by owner" on public.entitlements
  for select using (auth.jwt() ->> 'sub' = user_uid);

-- ============================================================
-- Realtime
-- ============================================================
alter publication supabase_realtime add table public.radar_events;
alter publication supabase_realtime add table public.profiles;

-- ============================================================
-- Minor-safety guard: force approximate precision for minor-protected rows
-- ============================================================
create or replace function public.enforce_minor_safety()
returns trigger as $$
begin
  if new.is_minor_protected then
    new.geo_precision := 'approximate';
    new.venue_name := null;
    -- keep area_name as the coarse label
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists radar_events_minor_safety on public.radar_events;
create trigger radar_events_minor_safety
  before insert or update on public.radar_events
  for each row execute function public.enforce_minor_safety();
