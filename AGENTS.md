# The Radar — Agent Working Agreement

Flutter web app (Pi Network TPA) + Supabase backend. Live URL (Pi container):
<https://radarvr7995.pinet.com> — a PiNet iframe shell around the real
deployment at <https://ayuni1234.github.io/the-radar/> (GitHub Pages, branch
`web-deploy`).

## Deployment standard — nothing sits stranded locally

Every completed task, feature, screen, or UI change MUST end shipped, not
left as local edits. Follow this workflow before ending any session or turn
in which files were changed:

1. **Verify State** — run `git status` and make sure every new and modified
   file is accounted for. Run the project's checks first (`flutter analyze`,
   `flutter test --exclude-tags=golden-capture`) so broken code never rides
   a deploy.
2. **Stage & Commit** — stage the relevant files explicitly (no blanket
   `git add -A`) and write a clear, descriptive commit message: what was
   added or updated and why. Follow the repo's existing commit style.
3. **Push to Main** — `git push origin main`. This triggers the GitHub
   Actions workflow (`Build & Deploy Web`): flutter analyze → test gate →
   Supabase `db push` (pending migrations) → `flutter build web` → publish
   to GitHub Pages → live on the Pi link within ~5 minutes.
4. **Remind the User** — once the push is complete (and ideally once the
   `web-deploy` branch shows the new `deploy: <sha>` commit), remind them to
   **hard-refresh the live link** (Ctrl+Shift+R, or clear the PWA cache)
   because Flutter web's service worker caches aggressively.

**Goal:** every completed feature must be compiled, pushed, and verified
live on <https://radarvr7995.pinet.com>. Never leave work uncommitted at
the end of a task.

## Supabase backend notes

- CLI runs through `npx supabase ...`; auth uses the `SUPABASE_ACCESS_TOKEN`
  repo secret on CI and a local login/token on dev machines.
- Project ref: `wmadurjharulfyyzzyes` ("Radar"). The link is machine-local
  (`supabase/.temp`, gitignored) — re-link with
  `npx supabase link --project-ref wmadurjharulfyyzzyes`.
- Migrations in `supabase/migrations/` must stay idempotent (see
  `0001_pitch_market.sql` for the house style).
- Edge functions live in `supabase/functions/` and are deployed manually
  (`npx supabase functions deploy <name>`) — not part of the web workflow.

## Test conventions

- Pixel-golden / screenshot capture tests are tagged `golden-capture`
  (see `dart_test.yaml`) and excluded from CI: goldens are
  OS/renderer-dependent and regenerate on dev machines only via
  `flutter test test/golden_radar_screen_test.dart --name capture
  --update-goldens`.
