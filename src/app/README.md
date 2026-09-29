# XAU Radar — Flutter app (`src/app/`)

MOCK_MODE build of the 5-screen MVP (spec §24): Radar · Signal · Sources ·
History · Settings. Harbor light-first design (mist `#E9ECEF`, cobalt
`#2347F5`); plain Material Icons stand in for the mockups' Flaticon UIcons
to keep the MVP fully offline.

> Display models in `lib/models/` are minimal LOCAL duplicates of the
> `xau_core` domain concepts — deliberately **not** path dependencies yet,
> to avoid cross-package version friction during the UI phase. Live wiring
> (T5.7) replaces them with the real packages or a thin mapper.

## Run

```powershell
cd src/app
flutter pub get
flutter run            # MOCK_MODE fixtures, no backend config needed
flutter analyze        # must be clean
flutter test           # must be green
```

`MOCK_MODE` lives in `lib/config.dart` (`const bool mockMode = true`).
`BackendService` (`lib/services/backend_service.dart`) wires
`supabase_flutter` + `firebase_core`/`firebase_messaging` but returns
immediately while mock mode is on, so zero Firebase/Supabase config is
required. Release builds assert mock mode until T5.7 lands.

## Decisions

- **State:** `provider` (`AppState` ChangeNotifier) — single store for tab
  routing, mock-scenario preview, TP selection, source toggles, Settings.
  In-memory for now; Supabase user preferences in T5.7.
- **Deps:** `provider` (state), `supabase_flutter` (idle behind flag),
  `firebase_core` + `firebase_messaging` (token registration only,
  guarded). No `url_launcher` — "View Original" shows a placeholder
  snackbar `Opens <url>` until T5.7 opens URLs externally.
- **Scope:** exactly 5 screens + bottom nav. No Events screen, no charts,
  no auth — all deferred per spec §24 exclusions.
- **Agreement, not forecasts:** strength renders as band label + score
  (`STRONG 82`, `82/100`) only; a widget test fails the build if forecast
  language ever renders.

## Stubbed for later phases (T5.7)

- `BackendService.init` — Supabase + Firebase init (needs `--dart-define`
  `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` + provisioned Firebase project).
- `BackendService.registerPushToken` — FCM token upsert to `push_tokens`.
- `BackendService.activeSignalStream` — live `consensus_signals` stream.
- Settings persistence → Supabase user preferences.
- "View Original" → external URL launch.
- Bundled Sora/Space Mono + UIcons-equivalent icon font.
