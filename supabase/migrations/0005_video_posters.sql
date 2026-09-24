-- ============================================================
-- Migration 0005 — Video poster frames for device video posts
--
-- `feed_posts` gains `media_poster_url`: the poster frame captured at
-- pick time (web canvas grab / native extractor) is uploaded alongside
-- the clip so feed cards can render a real video thumbnail hero
-- instantly — instead of a painted placeholder — without loading the
-- video itself.
--
-- The minor-poster privacy trigger is updated to strip poster URLs
-- whenever it would strip the media URL itself (link-kind posts): a
-- poster frame must never leak media the trigger removed.
--
-- Re-runnable (idempotent), same style as 0002_media_and_marketplace.sql.
-- ============================================================

alter table public.feed_posts
  add column if not exists media_poster_url text;

-- Poster URLs are the same `feed-media` storage the clips live in; the
-- text column needs no constraint beyond a sane length ceiling.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'feed_posts_media_poster_url_len'
  ) then
    alter table public.feed_posts
      add constraint feed_posts_media_poster_url_len
      check (char_length(media_poster_url) <= 2048);
  end if;
end $$;

-- ------------------------------------------------------------
-- Privacy trigger: fence poster URLs alongside media URLs
-- ------------------------------------------------------------
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
    -- The poster frame belongs to the same media object — strip it
    -- whenever the media URL goes, so a fenced link cannot survive as a
    -- still frame.
    if new.media_kind is null or new.media_kind = 'link' then
      new.media_url := null;
      new.media_platform := null;
      new.media_poster_url := null;
    end if;

    -- The typed area label is a coarse, poster-authored text label — the
    -- same class of disclosure as the caption. It persists; the database
    -- still withholds every precise coordinate above.
  end if;
  return new;
end;
$$ language plpgsql;

-- (Trigger feed_posts_privacy already exists — it re-fires with the new
-- function body automatically.)
