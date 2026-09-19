# The Radar — Global Football Scouting Platform

Responsive **Flutter Web** app connecting football talent with verified scouts,
clubs, academies, agents and parents worldwide — with **Pi Network** identity
and payments and **Supabase** realtime sync.

```
lib/
├── main.dart                     # app entry, responsive shell & navigation
└── src/
    ├── pi/
    │   ├── pi_sdk_js.dart        # dart:js_interop bindings for window.Pi
    │   ├── pi_service.dart       # init / authenticate / createPayment facade
    │   └── pi_config.dart        # Pi environment config (v2.0 standard)
    ├── supabase/
    │   └── supabase_config.dart  # Supabase bootstrap + availability flag
    ├── models/                   # UserProfile, RadarEvent, PiPayment, enums
    ├── data/
    │   ├── radar_repository.dart # CRUD + realtime subscriptions
    │   └── demo_seed.dart        # offline demo dataset
    ├── state/                    # Riverpod controllers (auth, events, payments)
    └── ui/                       # login, radar map, profiles, payments, theme
supabase/
├── schema.sql                    # tables, RLS, realtime, minor-safety trigger
└── functions/
    ├── pi-payment-approve/       # server-side approval webhook
    └── pi-payment-complete/      # server-side completion + entitlements
```

## Features

### 1. Pi Network Authentication Bridge
- `window.Pi` is initialised from `pi-sdk.js` (loaded in `web/index.html`) via
  typed `dart:js_interop` bindings — `Pi.init({ version: '2.0' })`, the
  official v2.0 standard (no sandbox parameter).
- `Pi.authenticate(['username','payments'], onIncompletePaymentFound)` captures
  the access token (browser-side uid/username are display-only).
- The token is then **exchanged with App Studio**
  (`POST …/pi/auth/v1/login`), which verifies it against the Pi Platform;
  the returned uid/username are the only identity the app trusts, and the
  session token marks a verified sign-in. No Pi API key is needed for this.
- Incomplete payments found at sign-in are routed to the completion webhook for
  server-side recovery.

### 2. Live Interactive Map (Radar View)
- Custom-painted sweep radar (`CustomPaint` + `AnimationController`) with
  hit-tested blips for **training sessions, matches, trials, tournaments**.
- Blips are placed deterministically by event geo-coordinates (bearing from
  longitude, distance from latitude); boosted events sit nearer the center.
- Filters: event type chips, boosted-only, free-text search. Selection opens a
  detail sheet (desktop side panel / mobile bottom sheet).
- **Safety defaults:** events involving minors carry
  `geo_precision = 'approximate'` — the schema trigger strips venue names and
  the UI renders the coarse `area_name` only. A shield badge marks protected
  events; the policy is explained in-app.

### 3. Player & Scout Profiles
- Roles: **player, verified scout, club, academy, agent, parent** with icons
  and dedicated filter chips.
- Fields: football CV, positions, credibility score (0–100 with colour-coded
  meter), video showcase links, club affiliation, KYC badge, rating.
- Minor profiles are masked: coarse area label, moderated contact, explicit
  safeguarding notice in the detail view.

### 4. Pi Wallet Payments
- `Pi.createPayment(data, callbacks)` wrapped in a Dart `Stream<PiPaymentState>`
  covering `onReadyForServerApproval`, `onReadyForServerCompletion`, `onCancel`
  and `onError`.
- Products: **Premium Scouting Search (5 π / 30d)**, **Session Boost
  (2 π / 48h)**, **Scouting Bounty (10 π)**.
- Both SDK callbacks POST to Supabase Edge Functions which call
  `POST /v2/payments/{id}/approve` and `/complete` with the server API key,
  mirror the payment into `pi_payments`, and grant rows in `entitlements`.

### 5. Supabase Integration
- `supabase_flutter` with `--dart-define` credentials; realtime
  `postgres_changes` subscriptions keep profiles & radar events live.
- Repository pattern falls back to a built-in demo dataset when Supabase or Pi
  credentials are absent, so the app is fully explorable offline.

## Getting started

```bash
flutter pub get

# Demo mode (no Supabase, no Pi SDK — plain browser):
flutter run -d chrome

# With Supabase (realtime + profiles):
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...your-anon-key

# Production (inside the Pi Browser):
flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
# then deploy build/web to your hosting and register the URL in the
# Pi Developer Portal (develop.pi in the Pi Browser).
```

### Backend setup

1. Run `supabase/schema.sql` in the Supabase SQL editor.
2. Deploy the edge functions:
   ```bash
   supabase functions deploy pi-payment-approve
   supabase functions deploy pi-payment-complete
   supabase secrets set PI_API_KEY=your-pi-server-api-key
   ```
3. Environment: `Pi.init({ version: '2.0' })` — the official v2.0 standard,
   with no sandbox parameter. Sandbox vs production is decided by which URL is
   registered in the Pi Developer Portal (open `develop.pi` in the Pi Browser);
   testnet payments are identified by `PaymentDTO.network = "PiTestnet"`. The
   Platform API base is the same for both networks (`api.minepi.com/v2`).

### Pi environment matrix

| Build target                | Environment                        | Behaviour                                      |
|-----------------------------|-------------------------------------|------------------------------------------------|
| `flutter run` (Chrome)      | plain browser (no `window.Pi`)     | SDK absent → demo login, no real payments      |
| Pi Browser, sandbox URL     | Developer Portal dev URL           | **Testnet** payments (`network: "PiTestnet"`)  |
| Pi Browser, production URL  | Developer Portal production URL    | Mainnet authentication & U2A payments          |

> Outside the Pi Browser `window.Pi` does not exist; the login screen detects
> this and explains the demo fallback instead of failing.

## Security model

- **Client never trusts client**: the access token from `Pi.authenticate` is
  display-only; identity is verified server-side via the Platform API `/me`.
- **Server API key stays server-side** — only edge functions hold `PI_API_KEY`.
- **Minors**: approximate location enforced by a Postgres trigger *and* the UI;
  exact venue names are stripped at the database level even if a client is
  compromised.
- **Payments**: approval/completion require the backend; a client cannot mark a
  payment complete without a Pi-verified `txid`.

## Next steps (roadmap)

- Messaging & contact requests with moderation queue for minor accounts.
- Scout report templates tied to bounty payouts (A2U payments).
- Geohash column + PostGIS proximity queries for a true map tile layer.
