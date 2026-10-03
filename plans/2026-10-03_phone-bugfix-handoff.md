# Session hand-off — XV (XAU-Vote)

Paused mid-way through a bug-fix batch reported from the phone. Production
code is written and compiles; **8 tests are red** because they still assert the
old TP-all default. Nothing is lost, and the exact resume point is below.

State at pause: `main`, clean tree, HEAD `1f8a60d`, no uncommitted work.

---

## The 7 reported bugs

| # | Report | Status | Where |
|---|---|---|---|
| 1 | Timeframe switcher (15M/5M/1H) does nothing | **Fixed** | `TimeframeSwitch` had no tap handler *by design*; `RadarScreen` is now stateful and owns the selection |
| 2 | Trade idea still shown while market closed | **Fixed** | `RadarScreen._MarketClosedCard`, `SignalScreen._MarketClosedNotice` — levels are withheld, with a "reopens in" countdown |
| 3 | Sources page shows no sources | **Fixed** | `sources_screen.dart` hardcoded `const <DisplaySource>[]` in live mode; now reads `LiveData.contributors` from a new `contributingSources()` query |
| 4 | History rows not tappable, poor design | **NOT STARTED** | `history_screen.dart` — needs a detail sheet |
| 5 | Countdown `1941:33:44`, laggy, not smooth | **Fixed** | `formatCountdown` now scales MM:SS / HH:MM:SS / `6d 03:20`; `EventCountdown` derives from an absolute target and re-derives its tick interval |
| 6 | Bell button unclear, item seems to swap | **NOT STARTED** | `events_screen.dart` `_MuteBell` + `_nextBlackout` — muting a HIGH USD event changes the top blackout card, which reads as a swap |
| 7 | No notification permission prompt | **NOT STARTED** | `backend_service.dart` deliberately never initialises FCM |
| 8 | Market-status pulse | **Fixed** | `PulseDot`, port of Uiverse "Loader" by Yaya12085 (MIT) |
| 9 | TP1-only default | **Fixed** | `AppState._targets` |

---

## Resume here

### Step 1 — finish the TP1 default (the 8 red tests)

The default target scope is now `TargetSelection.tp1Only`, so TP2 and TP3 are
withheld. These tests still expect them:

```
test/radar_test.dart        Radar verdict card shows levels, targets and agreement
                            Bottom nav routes from Radar to the Signal tab
test/signal_test.dart       Signal shows levels, timeline, context and TP control
                            Signal TP selector narrows the visible targets
                            No rendered text frames agreement as a forecast
test/pip_convention_test.dart  B renders the documented figures and one-line cells
                                picking A rescales the readouts and nothing else
                                390px layout no tab overflows or wraps a one-line string
```

All fail the same way: `4,315` / `4,340` (TP2 / TP3) not found.

**Do not weaken the assertions — decide per test:**

- a test about the *target selector* should set the scope explicitly, e.g.
  `TargetSelection.all`, then narrow, so it measures narrowing rather than the
  default;
- a test about something else (pip scaling, layout, copy) should also pin the
  scope so it does not depend on the default.

`radar_test.dart` already has a working helper for this:

```dart
Future<void> _setTargets(WidgetTester tester, TargetSelection targets) async {
  final state = Provider.of<AppState>(
    tester.element(find.byType(RadarScreen)),
    listen: false,
  );
  state.setTargets(targets);
  await tester.pumpAndSettle();
}
```

Note: `XauVoteApp` builds its **own** `AppState`, so wrapping it in an outer
provider is silently shadowed — reach the state through the rendered tree as
above. `radar_test.dart` already imports `provider`, `models/display_models.dart`,
`state/app_state.dart` and `screens/radar_screen.dart`; `signal_test.dart` and
`pip_convention_test.dart` still need those imports.

### Step 2 — the three unstarted bugs

**History rows tappable.** `_HistoryRow` in `history_screen.dart` renders a
static card. Needs an `InkWell` + `showModalBottomSheet` showing entry, stop,
each TP, outcome and pips. `DisplayHistoryEntry` currently carries only
`whenText`, `detailText`, `status` and `pipsPoints` — the detail sheet needs
those fields to be useful, so widen the model (and `LiveRepository._toHistoryEntry`)
rather than showing a sheet full of placeholders.

**Mute bell.** Two problems:
1. Muted rows render at `Opacity(0.45)`, which reads as *disabled* rather than
   *muted*. Prefer an explicit "MUTED" chip and full opacity, or a muted colour
   on the bell only.
2. `_nextBlackout` skips muted events, so muting the soonest HIGH USD event
   promotes the next one into the top card. That is why the first row "seems to
   swap". Either keep the card pinned to the soonest HIGH USD event and show its
   muted state, or make the card's change explicit. Confirm which the user wants
   — do not guess, this is a behaviour question, not a bug.

Also: `onToggleMute` currently only mutates a local `Set` and never persists,
and it is not wired to the notification toggles in `AppState`. Decide whether
muting an event should suppress that event's alerts only (needs persistence and
real push wiring) or is purely a local display filter.

**Notification permission.** `BackendService.init()` deliberately skips Firebase
because no FCM server key exists. Requesting permission without a working
delivery path is worse than not asking: it would take a permission the app
cannot honour. Either wire FCM properly (server key + `push_tokens` table +
Edge Function sender), or add an in-app prompt that explains alerts are not yet
delivered. Do not add a bare `requestPermission()` call.

### Step 3 — icon pass via streamline MCP

The user asked for better icons. `lib/icons.dart` holds 18 Flaticon UIcons
codepoints. Per the Streamline MCP rules: call `search_families`, then
`get_all_sets_from_family` on the chosen family, and download from that one
family so the set still reads as a system. Attribution for UIcons must stay in
Settings if UIcons are replaced by Streamline — check the licence before
swapping, and update the "UIcons by Flaticon" micro-copy if the family changes.

---

## Decisions made in this session, do not undo

- **Offline builds treat the market as open.** `mockMode ? true : isSessionOpen(...)`
  in both Radar and Signal. The offline build is a UI preview over fixtures,
  makes no market-status claim (its header hides the pill), and gating it on the
  real calendar just blanks the design at weekends. Live builds read the clock.
- **`sessionOpenOverride`** exists on `RadarScreen` and `SignalScreen`,
  `@visibleForTesting`, so the live-mode suite is not calendar-dependent.
- **PulseDot only pulses when the market is genuinely open.** A pulsing dot on a
  closed market would assert activity that is not happening.
- **`PulseDot` uses a nullable `AnimationController`, not `late final`.** A
  `late final` initialiser can construct the controller inside `dispose()`, which
  throws "Looking up a deactivated widget's ancestor is unsafe". That bug was
  caught by the test suite.
- **Countdown stops ticking past its target** and renders `released` in
  `harborDim`, not a red `00:00`.

---

## Verify before declaring done

```powershell
cd C:\Users\HP\Documents\code_repo\xau-vote\src\app
flutter analyze                     # must be clean
flutter test                        # must be 110/110 green
cd ..\xau_core; dart analyze; dart test   # 251, unchanged
```

Then build, install and read the screens on the phone:

```powershell
cd C:\Users\HP\Documents\code_repo\xau-vote\src\app
flutter build apk --release `
  --dart-define=LIVE=true `
  --dart-define=SUPABASE_URL=https://mfrzwmqgwgcyaxehdbqh.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_RQuuxcbF5SyyDC0bkn0ZdQ_2jrrBfT6 `
  --dart-define=UPDATE_MANIFEST_URL=https://mfrzwmqgwgcyaxehdbqh.supabase.co/functions/v1/app-release
adb -s RFCWA0BJT9F install -r -d build\app\outputs\flutter-apk\app-release.apk
adb -s RFCWA0BJT9F shell am start -n com.xauvote.app/.MainActivity
adb -s RFCWA0BJT9F shell screencap -p /sdcard/x.png
adb -s RFCWA0BJT9F pull /sdcard/x.png "$env:TEMP\x.png"
```

**The device clock is a trap.** It reports Saturday while a market-open screen is
expected to differ by day, and screenshots taken at the weekend will show
MARKET CLOSED everywhere. To verify an open-market state, either set the device
date forward or pass `sessionOpenOverride` in a test — do not "fix" a screenshot
by deleting the closed-market branch.

---

## Unrelated but still open

- No release manifest published: `app-releases` is empty, so Settings → App
  updates reports the endpoint as having nothing. Publishing needs
  `SUPABASE_SERVICE_ROLE_KEY` and `publish-release.ps1`.
- The release keystore lives at `code_repo/xau-vote-keys/` and is **not backed
  up off this machine**. Losing it means never shipping an update to the app
  already installed on the phone.
- `analysis-scan`, `warm-bars` and `oanda-quote` Edge Functions were deployed
  directly through MCP and are still not mirrored under `supabase/functions/`.
