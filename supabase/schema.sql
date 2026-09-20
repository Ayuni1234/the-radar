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

-- Converge older live tables: rename the legacy KYC column and add any
-- columns introduced after the table was first created (create table if not
-- exists cannot do this on an existing table).
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'profiles'
               and column_name = 'is_kyc_verified')
     and not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'profiles'
                       and column_name = 'kyc_verified') then
    alter table public.profiles rename column is_kyc_verified to kyc_verified;
  end if;
end
$$;
alter table public.profiles add column if not exists credibility_score   numeric(5,2) not null default 0;
alter table public.profiles add column if not exists display_name        text;
alter table public.profiles add column if not exists bio                 text;
alter table public.profiles add column if not exists country             text;
alter table public.profiles add column if not exists city                text;
alter table public.profiles add column if not exists positions           text[] not null default '{}';
alter table public.profiles add column if not exists football_cv         text;
alter table public.profiles add column if not exists video_showcase_urls text[] not null default '{}';
alter table public.profiles add column if not exists club_affiliation    text;
alter table public.profiles add column if not exists is_minor            boolean not null default false;
alter table public.profiles add column if not exists geohash_area        text;
alter table public.profiles add column if not exists rating              numeric(3,2) not null default 0;
alter table public.profiles add column if not exists avatar_url          text;
alter table public.profiles add column if not exists onboarded_at        timestamptz;
alter table public.profiles add column if not exists updated_at          timestamptz not null default now();
-- Account settings: public-directory visibility (default on).
alter table public.profiles add column if not exists is_public           boolean not null default true;

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
  for select using (is_public or id = auth.uid());
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
drop policy if exists "users delete own profile" on public.profiles;
create policy "users delete own profile" on public.profiles
  for delete using (
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

-- Payments: service role writes; the verified payer reads their own receipts.
drop policy if exists "payments service only" on public.pi_payments;
create policy "payments service only" on public.pi_payments
  for select using (false);
drop policy if exists "payments readable by payer" on public.pi_payments;
create policy "payments readable by payer" on public.pi_payments
  for select using (user_uid = public.verified_pi_uid());
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
-- Module 3: Minor-Safety & Privacy Safeguards
-- ============================================================
-- Geofencing and consent are enforced at the DATABASE level, so they hold
-- no matter which client writes. Three layers:
--
--   1. radar_events       — minor-protected rows (and events hosted by
--                           minors) are forced to approximate precision;
--                           exact venue names are stripped.
--   2. profiles           — a minor's profile may only carry a coarse area
--                           label, never precise coordinates.
--   3. connection_requests— adults cannot approach a minor without the
--                           guardian's explicit consent.
--
-- Consent model (`guardian_links`): a minor invites a guardian; the
-- guardian approves and controls two independent switches, both OFF by
-- default:
--   consent_connections — adults may send contact requests to the minor
--   consent_events      — the minor may be invited to / apply for events
-- ============================================================

-- ------------------------------------------------------------
-- guardian_links: minor ↔ guardian relationship + consent switches
-- ------------------------------------------------------------
create table if not exists public.guardian_links (
  id                  uuid primary key default gen_random_uuid(),
  minor_profile       uuid not null references public.profiles(id) on delete cascade,
  guardian_profile    uuid not null references public.profiles(id) on delete cascade,
  status              text not null default 'pending'
                      check (status in ('pending','active','declined','revoked')),
  consent_connections boolean not null default false,
  consent_events      boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (minor_profile, guardian_profile)
);
create index if not exists guardian_links_minor_idx    on public.guardian_links (minor_profile);
create index if not exists guardian_links_guardian_idx on public.guardian_links (guardian_profile);

alter table public.guardian_links enable row level security;

-- Both parties see the link; nobody else can (the enforcement trigger below
-- reads it as SECURITY DEFINER, so secrecy here does not weaken safety).
drop policy if exists "guardian links visible to participants" on public.guardian_links;
create policy "guardian links visible to participants" on public.guardian_links
  for select using (minor_profile = auth.uid() or guardian_profile = auth.uid());
-- The MINOR invites their guardian (pending); the guardian approves.
drop policy if exists "guardian links invited by minor" on public.guardian_links;
create policy "guardian links invited by minor" on public.guardian_links
  for insert with check (minor_profile = auth.uid());
drop policy if exists "guardian links updated by participants" on public.guardian_links;
create policy "guardian links updated by participants" on public.guardian_links
  for update using (minor_profile = auth.uid() or guardian_profile = auth.uid());

-- Role guards: a minor can invite + revoke but can NEVER self-approve a
-- pending link or flip the consent switches — that power is guardian-only.
create or replace function public.guardian_link_insert_guards()
returns trigger as $$
begin
  if auth.uid() is not null and new.minor_profile = auth.uid()
     and new.status <> 'pending' then
    new.status := 'pending';  -- minors can only ever create invitations
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists guardian_links_insert_guard on public.guardian_links;
create trigger guardian_links_insert_guard
  before insert on public.guardian_links
  for each row execute function public.guardian_link_insert_guards();

create or replace function public.guardian_link_update_guards()
returns trigger as $$
begin
  if auth.uid() is null then
    return new;  -- service role / maintenance
  end if;
  if new.minor_profile = auth.uid() and new.guardian_profile <> auth.uid() then
    if old.status = 'pending' and new.status not in ('pending', 'revoked') then
      raise exception 'only the guardian can approve or decline a guardian link';
    end if;
    if new.consent_connections <> old.consent_connections
       or new.consent_events <> old.consent_events then
      raise exception 'only the guardian can change consent switches';
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists guardian_links_update_guard on public.guardian_links;
create trigger guardian_links_update_guard
  before update on public.guardian_links
  for each row execute function public.guardian_link_update_guards();

-- ------------------------------------------------------------
-- Consent lookup for UX pre-checks: booleans only, no PII. Any
-- authenticated user may call it; the real gate is the trigger below.
-- ------------------------------------------------------------
create or replace function public.minor_consent_status(p_minor uuid)
returns jsonb
language sql stable
security definer
set search_path = public as
$$
  select jsonb_build_object(
    'is_minor',
      coalesce((select p.is_minor from public.profiles p where p.id = p_minor), false),
    'consent_connections',
      coalesce((select bool_or(g.consent_connections)
                from public.guardian_links g
                where g.minor_profile = p_minor and g.status = 'active'), false),
    'consent_events',
      coalesce((select bool_or(g.consent_events)
                from public.guardian_links g
                where g.minor_profile = p_minor and g.status = 'active'), false)
  );
$$;

-- ------------------------------------------------------------
-- Layer 1 — events: fence minor-protected rows AND events hosted by minors
-- ------------------------------------------------------------
create or replace function public.enforce_minor_safety()
returns trigger as $$
declare
  host_is_minor boolean := false;
begin
  if new.host_profile_id is not null then
    select p.is_minor into host_is_minor
    from public.profiles p where p.id = new.host_profile_id;
  end if;
  if coalesce(host_is_minor, false) then
    new.is_minor_protected := true;   -- a minor's event is always fenced
  end if;
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

-- ------------------------------------------------------------
-- Layer 2 — profiles: minors carry only a coarse area label. If the coarse
-- label is missing, fall back to city — never to anything more precise.
-- ------------------------------------------------------------
create or replace function public.enforce_minor_profile_privacy()
returns trigger as $$
begin
  if new.is_minor then
    if new.geohash_area is null or btrim(new.geohash_area) = '' then
      new.geohash_area := coalesce(nullif(btrim(coalesce(new.city, '')), ''), 'Region withheld');
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_minor_privacy on public.profiles;
create trigger profiles_minor_privacy
  before insert or update on public.profiles
  for each row execute function public.enforce_minor_profile_privacy();

-- ------------------------------------------------------------
-- Layer 3 — connections: guardian consent gates every adult → minor
-- approach (SECURITY DEFINER so the check works even though
-- guardian_links are hidden from non-participants by RLS).
-- ------------------------------------------------------------
create or replace function public.enforce_minor_connection_consent()
returns trigger as $$
declare
  sender_is_minor     boolean := false;
  target_is_minor     boolean := false;
  sender_is_guardian  boolean := false;
  consent_connections boolean := false;
  consent_events      boolean := false;
begin
  select p.is_minor into sender_is_minor
    from public.profiles p where p.id = new.from_profile;
  select p.is_minor into target_is_minor
    from public.profiles p where p.id = new.to_profile;

  -- Adult approaching a minor.
  if coalesce(target_is_minor, false) and not coalesce(sender_is_minor, false) then
    -- The minor's approved guardian is always allowed through.
    select exists (
      select 1 from public.guardian_links g
      where g.minor_profile = new.to_profile
        and g.guardian_profile = new.from_profile
        and g.status = 'active'
    ) into sender_is_guardian;

    if not sender_is_guardian then
      select coalesce(bool_or(g.consent_connections), false),
             coalesce(bool_or(g.consent_events), false)
      into consent_connections, consent_events
      from public.guardian_links g
      where g.minor_profile = new.to_profile and g.status = 'active';

      if new.request_type = 'contact' and not consent_connections then
        raise exception 'minor_contact_blocked: guardian consent for connections is required';
      elsif new.request_type = 'trial_invite' and not consent_events then
        raise exception 'minor_event_blocked: guardian consent for event participation is required';
      elsif new.request_type = 'trial_application'
            and not (consent_connections or consent_events) then
        raise exception 'minor_contact_blocked: guardian consent is required';
      end if;
    end if;
  end if;

  -- A minor applying for an open trial themselves: participation consent.
  if coalesce(sender_is_minor, false) and new.request_type = 'trial_application' then
    select coalesce(bool_or(g.consent_events), false) into consent_events
    from public.guardian_links g
    where g.minor_profile = new.from_profile and g.status = 'active';
    if not consent_events then
      raise exception 'minor_event_blocked: guardian consent for event participation is required';
    end if;
  end if;

  return new;
end;
$$ language plpgsql
security definer
set search_path = public;

drop trigger if exists connection_requests_minor_consent on public.connection_requests;
create trigger connection_requests_minor_consent
  before insert on public.connection_requests
  for each row execute function public.enforce_minor_connection_consent();

-- ============================================================
-- Consent audit log (Module 3 — Guardian Consent Management)
-- Append-only record of every guardian permission change enforced by
-- the backend triggers. Written by SECURITY DEFINER trigger functions;
-- no client policy on purpose — the log is tamper-evident.
-- ============================================================
create table if not exists public.consent_audit_log (
  id          uuid primary key default gen_random_uuid(),
  minor_profile   uuid not null,
  guardian_profile uuid,
  link_id      uuid,
  action       text not null check (action in
               ('link_pending','link_active','link_declined','link_revoked',
                'consent_connections_on','consent_connections_off',
                'consent_events_on','consent_events_off')),
  actor_role   text not null check (actor_role in ('minor','guardian')),
  created_at   timestamptz not null default now()
);
create index if not exists consent_audit_minor_idx
  on public.consent_audit_log (minor_profile, created_at desc);
alter table public.consent_audit_log enable row level security;
-- No policies: rows are inserted by definer-rights triggers and read via
-- the SECURITY DEFINER function below (participant-scoped, no PII beyond
-- what the viewer is already entitled to).

-- Writes one audit row. Definer rights so the client never needs write
-- access to the log; IDs are captured before the mutation on guardian_links.
create or replace function public.write_consent_audit(
  p_minor uuid, p_guardian uuid, p_link uuid, p_action text, p_actor text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.consent_audit_log
    (minor_profile, guardian_profile, link_id, action, actor_role)
  values (p_minor, p_guardian, p_link, p_action, p_actor);
end;
$$;

-- Participant-scoped read (minor or guardian of the row sees their history).
create or replace function public.read_consent_audit()
returns setof public.consent_audit_log
language sql security definer set search_path = public as $$
  select a.* from public.consent_audit_log a
  where a.minor_profile = auth.uid() or a.guardian_profile = auth.uid()
  order by a.created_at desc
  limit 200;
$$;
grant execute on function public.read_consent_audit() to authenticated;
revoke insert, update, delete on public.consent_audit_log from authenticated;

-- Audit triggers on guardian_links: capture every status/consent change.
create or replace function public.audit_guardian_link_changes()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_actor text := case when new.guardian_profile = auth.uid()
                  then 'guardian' else 'minor' end;
begin
  if tg_op = 'INSERT' then
    perform public.write_consent_audit(
      new.minor_profile, new.guardian_profile, new.id,
      'link_pending', v_actor);
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      perform public.write_consent_audit(
        new.minor_profile, new.guardian_profile, new.id,
        case new.status
          when 'active' then 'link_active'
          when 'declined' then 'link_declined'
          when 'revoked' then 'link_revoked'
          else 'link_pending' end,
        v_actor);
    end if;
    if new.consent_connections is distinct from old.consent_connections then
      perform public.write_consent_audit(
        new.minor_profile, new.guardian_profile, new.id,
        case when new.consent_connections
          then 'consent_connections_on' else 'consent_connections_off' end,
        v_actor);
    end if;
    if new.consent_events is distinct from old.consent_events then
      perform public.write_consent_audit(
        new.minor_profile, new.guardian_profile, new.id,
        case when new.consent_events
          then 'consent_events_on' else 'consent_events_off' end,
        v_actor);
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists guardian_links_audit on public.guardian_links;
create trigger guardian_links_audit
  after insert or update of status, consent_connections, consent_events
  on public.guardian_links
  for each row execute function public.audit_guardian_link_changes();

-- ============================================================
-- Admin diagnostics (System Health page). SECURITY DEFINER so the
-- dashboard can read catalog-level state (policies, triggers, tables)
-- that anon/authenticated roles cannot see directly. Read-only.
-- ============================================================
create or replace function public.security_diagnostics()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tables  jsonb;
  v_policies jsonb;
  v_triggers jsonb;
  v_functions jsonb;
  v_publication text;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'table', c.relname, 'rls', c.relrowsecurity)), '[]')
    into v_tables
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('profiles','radar_events','connection_requests',
                       'guardian_links','entitlements','pi_payments',
                       'pi_sessions','consent_audit_log');

  select coalesce(jsonb_agg(jsonb_build_object(
           'table', tablename, 'policy', policyname, 'cmd', cmd)), '[]')
    into v_policies
    from pg_policies
   where schemaname = 'public';

  select coalesce(jsonb_agg(jsonb_build_object(
           'table', tgrelid::regclass::text,
           'trigger', t.tgname,
           'function', p.proname,
           'enabled', t.tgenabled = 'O')), '[]')
    into v_triggers
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
   where not t.tgisinternal
     and p.proname in ('enforce_minor_safety','enforce_minor_profile_privacy',
                       'enforce_minor_connection_consent',
                       'audit_guardian_link_changes');

  select coalesce(jsonb_agg(jsonb_build_object('function', proname)), '[]')
    into v_functions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('verified_pi_uid','minor_consent_status',
                       'read_consent_audit','write_consent_audit',
                       'audit_guardian_link_changes');

  select count(*)::text into v_publication
    from pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename in ('radar_events','profiles');

  return jsonb_build_object(
    'tables', v_tables,
    'policies', v_policies,
    'triggers', v_triggers,
    'functions', v_functions,
    'realtime_tables', v_publication
  );
end;
$$;
grant execute on function public.security_diagnostics() to authenticated;
