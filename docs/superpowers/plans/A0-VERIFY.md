# A0 Verification Notes

Date: 2026-06-30 · Branch: `feat/app-a0`

## What was verified (controller-run)

| Check | Command | Result |
|---|---|---|
| Server test suite | `server/.venv/bin/python -m pytest server/tests/ -q` | **8 passed**, 1 warning (third-party Starlette/httpx deprecation, unfixable without httpx2) |
| Flutter test suite | `cd app && flutter test` | **8 passed** |
| Flutter analyze | `cd app && flutter analyze` | No issues found |
| Flutter web build | `cd app && flutter build web` | **✓ Built build/web** (21.8s) |
| API health | `GET /health` | `{"status":"ok"}` |
| API submit | `POST /songs {url: youtu.be/dQw4w9WgXcQ}` | 200 — `yt-dlp` fetched real title ("Rick Astley - Never Gonna Give You Up … 4K Remaster") + duration 213s; stub pipeline returned key `C major`, 426 beats, 213 chord cells |
| API fetch (cache) | `GET /songs/dQw4w9WgXcQ` | 200 — same analysis from cache |
| API recent | `GET /songs` | lists the analyzed song |

The API smoke test ran the server on a throwaway SQLite file (`DATABASE_URL=sqlite:////tmp/cm_smoke.db`) so it needs no Postgres. In normal dev the server uses Postgres via `server/docker-compose.yml`.

## Not verified here (manual / on-device)

- Interactive web click-through (`flutter run -d chrome`): paste URL → Analyze → player → tap chord cell opens guitar+piano diagram sheet → toggle OS dark mode. Build succeeds; visual/interaction pass is for the developer on web or a real device.
- Real YouTube **audio playback timing** and native behaviors — on real device (per the spec's testing split).

## A0 done criteria — met
Paste YouTube link → server returns (stubbed) AnalysisResult → app shows synced chord grid + guitar/piano diagrams + lyrics/placeholder tabs + light/dark theme. Server + app build and all tests pass. Re-harm/Band/Versions are placeholder tabs. Real models, sync (A2), and versioning (A3) are deferred to later plans.

## Batched for the final review / follow-up
- `ChordMindColors.lerp` ignores `t` (no animated theme transitions in A0).
- 1 third-party Starlette/httpx test warning (needs `httpx2`, out of our control).
