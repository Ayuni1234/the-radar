-- ============================================================
-- Migration 0002 — Device media uploads + live marketplace wiring
--
-- 1. `feed-media` public Storage bucket for device uploads (training
--    videos ≤ 3 min + photos). Owner-scoped write; public read.
-- 2. `feed_posts` gains media_kind / media_duration_s so the feed can
--    render device video vs. link vs. photo distinctly (the 3-minute
--    highlight cap is enforced client-side before upload).
--
-- Re-runnable (idempotent), same style as 0001_pitch_market.sql.
-- ============================================================

-- ------------------------------------------------------------
-- Storage: public bucket for feed media
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'feed-media',
  'feed-media',
  true,
  209715200, -- 200 MB hard ceiling; the app enforces 3 min / 10 MB itself
  array[
    'video/mp4', 'video/quicktime', 'video/webm',
    'image/jpeg', 'image/png', 'image/webp'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Anyone (incl. anon) can view feed media — it backs the public feed.
drop policy if exists "feed media is publicly readable" on storage.objects;
create policy "feed media is publicly readable" on storage.objects
  for select using (bucket_id = 'feed-media');

-- Authenticated users write only under their own uid/ prefix.
drop policy if exists "users upload own feed media" on storage.objects;
create policy "users upload own feed media" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'feed-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users manage own feed media" on storage.objects;
create policy "users manage own feed media" on storage.objects
  for update to authenticated using (
    bucket_id = 'feed-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "users delete own feed media" on storage.objects;
create policy "users delete own feed media" on storage.objects
  for delete to authenticated using (
    bucket_id = 'feed-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ------------------------------------------------------------
-- feed_posts: distinguish device uploads from external links
-- ------------------------------------------------------------
alter table public.feed_posts
  add column if not exists media_kind text
    check (media_kind in ('link', 'device_video', 'device_photo'));

alter table public.feed_posts
  add column if not exists media_duration_s integer
    check (media_duration_s is null or media_duration_s <= 180);

-- Backfill: existing rows are link-style embeds.
update public.feed_posts
   set media_kind = 'link'
 where media_url is not null
   and media_kind is null;
