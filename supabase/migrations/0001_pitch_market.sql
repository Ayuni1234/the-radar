-- ============================================================
-- Migration 0001 — The PitchMarket (P2P streaming-gear marketplace)
-- Localized peer-to-peer equipment marketplace: merchant shops +
-- gear listings, bought outright with Pi coins through the
-- `market-checkout` edge function (U2A buyer payment + A2U merchant
-- payout split).
--
-- Re-runnable (idempotent), same style as supabase/schema.sql.
-- ============================================================

-- Identity helper: the verified Pi uid carried in the minted session's
-- app_metadata (provisioned by the `pi-session` edge function). Defined
-- here too so this migration is self-contained.
create or replace function public.verified_pi_uid()
returns text language sql stable as
$$ select nullif(auth.jwt() -> 'app_metadata' ->> 'pi_uid', '') $$;

-- ------------------------------------------------------------
-- market_shops: merchant storefronts
-- ------------------------------------------------------------
create table if not exists public.market_shops (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  shop_name     text not null,
  description   text,
  pi_uid        text not null,          -- vendor's verified Pi account for direct payouts
  location_area text not null,
  is_verified   boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists market_shops_owner_idx on public.market_shops (owner_id);

-- One storefront per merchant.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.market_shops'::regclass and conname = 'market_shops_owner_unique'
  ) then
    alter table public.market_shops
      add constraint market_shops_owner_unique unique (owner_id);
  end if;
end $$;

-- ------------------------------------------------------------
-- market_listings: gear inventory (phones, gimbals, tripods, audio, lighting)
-- ------------------------------------------------------------
create table if not exists public.market_listings (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references public.market_shops(id) on delete cascade,
  title          text not null,
  category       text not null
                 check (category in ('phone','gimbal','tripod','audio','lighting','accessory')),
  price_pi       numeric(12,4) not null check (price_pi >= 0),
  condition      text not null
                 check (condition in ('brand_new','like_new','good')),
  stock_quantity integer not null default 1 check (stock_quantity >= 0),
  media_urls     text[] not null default '{}',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);
create index if not exists market_listings_shop_idx
  on public.market_listings (shop_id);
create index if not exists market_listings_category_idx
  on public.market_listings (category);
create index if not exists market_listings_active_idx
  on public.market_listings (is_active) where is_active;

-- ============================================================
-- Row Level Security
-- Public: read shops + ACTIVE listings. Merchants: manage their own
-- shop and its listings (ownership flows through market_shops).
-- ============================================================
alter table public.market_shops    enable row level security;
alter table public.market_listings enable row level security;

drop policy if exists "market shops are readable" on public.market_shops;
create policy "market shops are readable" on public.market_shops
  for select using (true);

drop policy if exists "merchants create own shop" on public.market_shops;
create policy "merchants create own shop" on public.market_shops
  for insert with check (
    owner_id = auth.uid() and pi_uid = public.verified_pi_uid()
  );

drop policy if exists "merchants manage own shop" on public.market_shops;
create policy "merchants manage own shop" on public.market_shops
  for update using (owner_id = auth.uid());

drop policy if exists "merchants delete own shop" on public.market_shops;
create policy "merchants delete own shop" on public.market_shops
  for delete using (owner_id = auth.uid());

-- Everyone reads active listings; owners also see their own inactive rows.
drop policy if exists "active listings are readable" on public.market_listings;
create policy "active listings are readable" on public.market_listings
  for select using (
    is_active
    or exists (
      select 1 from public.market_shops s
      where s.id = shop_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "merchants create own listings" on public.market_listings;
create policy "merchants create own listings" on public.market_listings
  for insert with check (
    exists (
      select 1 from public.market_shops s
      where s.id = shop_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "merchants manage own listings" on public.market_listings;
create policy "merchants manage own listings" on public.market_listings
  for update using (
    exists (
      select 1 from public.market_shops s
      where s.id = shop_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "merchants delete own listings" on public.market_listings;
create policy "merchants delete own listings" on public.market_listings
  for delete using (
    exists (
      select 1 from public.market_shops s
      where s.id = shop_id and s.owner_id = auth.uid()
    )
  );
