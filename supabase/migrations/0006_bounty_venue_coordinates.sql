-- ============================================================
-- Migration 0006 — Bounty venue coordinates (idempotent)
--
-- The bounty's latitude/longitude are the poster's region centroid, not the
-- pitch. The GPS check-in geofence needs the venue pin, stored separately.
-- ============================================================

alter table public.stream_bounties
  add column if not exists venue_latitude double precision,
  add column if not exists venue_longitude double precision;
