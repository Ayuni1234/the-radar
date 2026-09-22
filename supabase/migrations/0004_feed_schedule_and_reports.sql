-- ============================================================
-- 0004 — Feed scheduling, content reports & minor-poster media policy
--
-- 1. feed_posts.scheduled_at — lets players attach a training/match
--    schedule directly to a post (the feed card's Calendar pill and
--    countdown chips render it).
-- 2. Minor-poster media policy: device uploads through OUR moderated
--    `feed-media` bucket are allowed for minors; external links
--    (YouTube/Drive/…) stay stripped. The typed area label also now
--    persists (it is a coarse text label by design), while exact
--    coordinates remain nulled for minors — the non-negotiable rule.
-- 3. content_reports — report-content flow with RLS:
--      • any authenticated user can file a report for a post/event/listing
--      • reporters see only their own reports
--      • admins (profiles.is_admin) see all reports and own the
--        status workflow (open → reviewing → resolved/dismissed)
-- ============================================================

-- ---------------------------------------------------------------- 1. schedule
alter table public.feed_posts
  add column if not exists scheduled_at timestamptz;

-- ------------------------------------------------------- 2. admin capability
-- Set only by operators in SQL (never through the client API): the column
-- has no client-writable policy path because profile upserts from the app
-- never include it (UserProfile.toJson omits it).
alter table public.profiles
  add column if not exists is_admin boolean not null default false;

create index if not exists feed_posts_scheduled_at_idx
  on public.feed_posts (scheduled_at)
  where scheduled_at is not null;

-- ------------------------------------------- 3. relaxed minor media policy
create or replace function public.enforce_feed_post_privacy()
returns trigger as $$
declare
  poster_is_minor boolean := false;
begin
  select coalesce(p.is_minor, false)
    into poster_is_minor
  from public.profiles p where p.id = new.author_profile_id;

  new.is_minor_poster := poster_is_minor;

  if poster_is_minor then
    -- Exact coordinates NEVER leave the database for minors.
    new.latitude := null;
    new.longitude := null;

    -- Device uploads to our moderated storage stay; external links are
    -- stripped (they can embed tracking/doxx vectors we cannot moderate).
    if new.media_kind is null or new.media_kind = 'link' then
      new.media_url := null;
      new.media_platform := null;
    end if;

    -- The typed area label is a coarse, poster-authored text label — the
    -- same class of disclosure as the caption. It persists; the database
    -- still withholds every precise coordinate above.
  end if;
  return new;
end;
$$ language plpgsql;

-- (Trigger feed_posts_privacy already exists from 0003 — it re-fires with
-- the new function body automatically.)

-- ------------------------------------------------------- 4. content_reports
create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_profile_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  target_type text not null
    check (target_type in ('feed_post', 'radar_event', 'market_listing')),
  target_id uuid not null,
  reason text not null
    check (reason in ('spam','abuse','inappropriate_media',
                      'misleading','minor_safety','other')),
  details text,
  status text not null default 'open'
    check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id)
);

alter table public.content_reports enable row level security;

-- A reporter can't stack duplicate OPEN reports on the same target.
create unique index if not exists content_reports_one_open_per_target
  on public.content_reports (reporter_profile_id, target_type, target_id)
  where status = 'open';

create index if not exists content_reports_open_idx
  on public.content_reports (status, created_at);

-- File: any authenticated user, as themselves.
drop policy if exists "reporters file own reports" on public.content_reports;
create policy "reporters file own reports" on public.content_reports
  for insert to authenticated
  with check (reporter_profile_id = auth.uid());

-- Read: your own reports, or everything if you are an admin.
drop policy if exists "own reports or admin" on public.content_reports;
create policy "own reports or admin" on public.content_reports
  for select using (
    reporter_profile_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.is_admin
    )
  );

-- Status workflow: admins only (and only operator SQL grants is_admin).
drop policy if exists "admins moderate reports" on public.content_reports;
create policy "admins moderate reports" on public.content_reports
  for update using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.is_admin
    )
  );
