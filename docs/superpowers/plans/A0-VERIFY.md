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

## Final whole-branch review: ✅ Ready to merge
Clean Architecture holds both sides; server↔client `AnalysisResult` contract matches field-for-field; chord-grid sync confirmed coherent (units + indexing line up); no resource leaks; commits clean. One Important finding was fixed (bad URL → 400 + UI SnackBar, commit `b6a3328`).

## Deferred to A1 (when real models land) — not A0 defects
- **Contract golden test:** add an automated cross-check that the server's `to_dict()` output parses into the Dart `AnalysisResult` (today both sides hand-build matching JSON; a shared golden fixture would catch drift). Recommended before A1.
- **Piano diagram** renders only the 7 white keys (`piano_diagram.dart`); black-key (sharp/flat) chords render incomplete. Fine for the C/G/Am/F fixture; fix when real chords appear.
- **Guitar painter** ignores `baseFret`/`barres` (e.g. F's barre not drawn) — cosmetic.
- **`grid_sync` RangeError guard:** add a bounds check on `beatIndex` when real slots can emit out-of-range indices.
- **`recent()`** endpoint + client method exist but no screen lists recents (dead until a "recent songs" UI is added).
- `ChordMindColors.lerp` ignores `t` (no animated theme transitions in A0).
- 1 third-party Starlette/httpx test warning (needs `httpx2`, out of our control).
