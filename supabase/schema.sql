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
  dominant_foot     text check (dominant_foot in ('left','right')),
  birth_year        integer,
  height_cm         integer,
  football_cv       text,
  video_showcase_urls text[] not null default '{}',
  club_affiliation  text,
  is_minor          boolean not null default false,
  geohash_area      text,                            -- coarse area label (minors: only this)
  rating            numeric(3,2) not null default 0,
  avatar_url        text,
  onboarded_at      timestamptz,                   -- null = onboarding not completed
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

-- Position requirements a host asks for (e.g. '{ST,CM}' on a trial).
alter table public.radar_events add column if not exists positions_required text[] not null default '{}';

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

-- ------------------------------------------------------------
-- pi_sessions: audit of App Studio-verified sign-ins (service-role only).
-- One row per successful server-side token exchange.
-- ------------------------------------------------------------
create table if not exists public.pi_sessions (
  id            uuid primary key default gen_random_uuid(),
  pi_uid        text not null,
  username      text,
  session_token text,
  created_at    timestamptz not null default now()
);
create index if not exists pi_sessions_uid_idx on public.pi_sessions (pi_uid);

-- ------------------------------------------------------------
-- connection_requests: P2P scouting connections (Module 4)
-- from_profile/to_profile reference profiles.id; direction + type tell the
-- story: scouts request player contact, players apply to events, organizers
-- invite players to trials.
-- ------------------------------------------------------------
create table if not exists public.connection_requests (
  id            uuid primary key default gen_random_uuid(),
  from_profile  uuid not null references public.profiles(id) on delete cascade,
  to_profile    uuid not null references public.profiles(id) on delete cascade,
  request_type  text not null default 'contact'
                check (request_type in ('contact','trial_invite','trial_application')),
  event_id      uuid references public.radar_events(id) on delete set null,
  message       text,
  status        text not null default 'pending'
                check (status in ('pending','accepted','declined','withdrawn')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists connection_requests_to_idx on public.connection_requests (to_profile);
create index if not exists connection_requests_from_idx on public.connection_requests (from_profile);

-- ============================================================
-- Row Level Security
--
-- Identity model: Pi users are provisioned by the `pi-session` edge
-- function with a Supabase auth user whose id is a deterministic UUID of
-- the App Studio-verified pi_uid, and whose app_metadata.pi_uid carries
-- that verified uid. RLS therefore keys on auth.uid() / verified_pi_uid()
-- — never on values supplied by the client.
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.radar_events enable row level security;
alter table public.pi_payments  enable row level security;
alter table public.entitlements enable row level security;
alter table public.pi_sessions  enable row level security;
alter table public.connection_requests enable row level security;

-- The verified Pi uid, taken from the minted session's app_metadata.
create or replace function public.verified_pi_uid()
returns text language sql stable as
$$ select nullif(auth.jwt() -> 'app_metadata' ->> 'pi_uid', '') $$;

-- Policies are dropped first so the whole file is safely re-runnable
-- (Postgres has no CREATE POLICY IF NOT EXISTS).
drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are readable" on public.profiles
  for select using (true);
-- Users manage only the profile provisioned for their verified identity:
-- profile id == auth.uid() AND pi_uid matches the verified claim.
drop policy if exists "users insert own profile" on public.profiles;
create policy "users insert own profile" on public.profiles
  for insert with check (
    id = auth.uid() and pi_uid = public.verified_pi_uid()
  );
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles
  for update using (
    id = auth.uid() and pi_uid = public.verified_pi_uid()
  );

-- Events are publicly readable (approximate data for minor-protected rows).
drop policy if exists "events are readable" on public.radar_events;
create policy "events are readable" on public.radar_events
  for select using (true);
-- Hosts manage their own events: host profile id == auth.uid().
drop policy if exists "hosts manage own events" on public.radar_events;
create policy "hosts manage own events" on public.radar_events
  for all using (host_profile_id = auth.uid());

-- Payments: service role (edge functions) only.
drop policy if exists "payments service only" on public.pi_payments;
create policy "payments service only" on public.pi_payments
  for select using (false);
-- Entitlements readable only by the verified owner.
drop policy if exists "entitlements readable by owner" on public.entitlements;
create policy "entitlements readable by owner" on public.entitlements
  for select using (user_uid = public.verified_pi_uid());
-- pi_sessions: audit table — no policies, service role only.

-- Connections: both parties see requests involving them; sender may withdraw
-- (update to 'withdrawn'), recipient may accept/decline.
drop policy if exists "connections visible to participants" on public.connection_requests;
create policy "connections visible to participants" on public.connection_requests
  for select using (from_profile = auth.uid() or to_profile = auth.uid());
drop policy if exists "connections created by sender" on public.connection_requests;
create policy "connections created by sender" on public.connection_requests
  for insert with check (from_profile = auth.uid());
drop policy if exists "connections updated by participants" on public.connection_requests;
create policy "connections updated by participants" on public.connection_requests
  for update using (from_profile = auth.uid() or to_profile = auth.uid());

-- ============================================================
-- Realtime (guarded so re-runs don't error on existing members)
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'radar_events'
  ) then
    alter publication supabase_realtime add table public.radar_events;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end
$$;

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
