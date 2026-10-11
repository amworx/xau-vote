/// XAU Radar — free, mobile-first day-trading assistant for XAUUSD.
///
/// Harbor light-first theme, 6 screens (Radar · Signal · Sources ·
/// History · Settings · Events) behind a bottom nav, provider state,
/// MOCK_MODE fixtures by default. See README.md for scope and live-wire stubs.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/analysis_service.dart';
import 'data/live_data.dart';
import 'icons.dart';
import 'screens/events_screen.dart';
import 'screens/history_screen.dart';
import 'screens/radar_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signal_screen.dart';
import 'screens/sources_screen.dart';
import 'services/backend_service.dart';
import 'services/update_service.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/pull_to_refresh.dart';
import 'widgets/update_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guarded: returns immediately in MOCK_MODE (zero config required).
  await BackendService.init();
  runApp(const XauVoteApp());
}

/// Root widget. Owns the [AppState] provider so the widget tree (and widget
/// tests pumping [XauVoteApp] directly) always has state available.
///
/// In live mode the widget tree additionally receives a [LiveData] provider so
/// screens can read the real backend; in offline mode it is absent and the
/// screens fall back to [MockFixtures].
class XauVoteApp extends StatelessWidget {
  const XauVoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ChangeNotifierProvider(
      // Load stored preferences before the first screen reads them, so a
      // restart shows the trader's actual choices rather than defaults for one
      // frame. Failures are swallowed inside AppState.load.
      create: (_) => AppState()..load(),
      child: const _Shell(),
    );

    // Live builds need Supabase initialised before any repository read. Guard
    // on `isReady` so a failed/absent init surfaces its own error screen
    // instead of throwing inside a widget build.
    if (!mockMode) {
      if (!BackendService.isReady) {
        return _StartupErrorScreen(
          message: BackendService.error ??
              'Live mode requested but Supabase did not initialise.',
        );
      }
      // Two independent pollers: LiveData carries the consensus/price snapshot
      // the screens already render, while AnalysisService runs the
      // multi-timeframe technical scan. They are kept separate so a slow or
      // failing analysis never stalls the price ticker.
return MultiProvider(
        providers: [
          ChangeNotifierProvider<LiveData>(
            create: (_) => LiveData()..startPolling(),
          ),
          ChangeNotifierProvider<AnalysisService>(
            create: (_) => AnalysisService()..startPolling(),
          ),
          // One UpdateService for the whole app, so the banner and the Settings
          // panel observe the SAME download. Provided as a nullable type because
          // an offline build has no manifest endpoint and must not be offered a
          // check that cannot succeed. The URL comes from public app config
          // (database first, build define as fallback) — never hardcoded.
          Provider<UpdateService?>.value(
            value: _updateManifest(),
          ),
        ],
        child: app,
      );
    }
    return app;
  }
}

/// Update manifest endpoint: public app config first, build define second.
///
/// Returns null (updater disabled, honest UNAVAILABLE) when neither yields a
/// usable absolute URL.
UpdateService? _updateManifest() {
  final fromDb = BackendService.updateManifestUrl;
  final fromBuild = updatesConfigured ? updateManifestUrl : null;
  final raw = (fromDb != null && fromDb.isNotEmpty) ? fromDb : fromBuild;
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.isAbsolute) return null;
  return UpdateService(manifestUrl: uri);
}

/// Shown when a live build cannot reach its backend. Never falls back to
/// fixtures: a trader must not mistake demo data for live data.
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: harborTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    HarborIcons.cross,
                    size: 28,
                    color: harborShort,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'LIVE DATA UNAVAILABLE',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 12,
                      height: 1.5,
                      color: harborDim,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'XV will not show demo data in place of live prices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      color: harborFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  /// Index order matches [HarborNavBar._items] and the mockup nav.
  static const _screens = [
    RadarScreen(),
    SignalScreen(),
    SourcesScreen(),
    HistoryScreen(),
    EventsScreen(),
    SettingsScreen(),
  ];

@override
  Widget build(BuildContext context) {
    final tabIndex = context.watch<AppState>().tabIndex;
    return MaterialApp(
      title: 'XV - XAU-Vote',
      debugShowCheckedModeBanner: false,
      theme: harborTheme(),
      home: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          backgroundColor: harborMist,
        ),
        body: SafeArea(
          // NOTE: shows only the selected screen instead of an IndexedStack:
          // offstage ListView viewports inside an IndexedStack crash the
          // semantics/tree walk under `flutter test` (Flutter 3.44).
          // Scroll offsets survive via PageStorageKeys on each screen list.
          //
          // Pull-to-refresh is applied here, once, rather than in each screen:
          // it must work on all six, and six copies would be six places for the
          // gesture to be wired to a different fetch.
          child: withPullToRefresh(context, _screens[tabIndex]),
        ),
        // Rendered in `bottomNavigationBar` (not stacked over the body) so
        // the screen list is laid out above it and never scrolls underneath.
        //
        // The banner sits INSIDE this slot, directly above the pill, so the two
        // stack as one bottom cluster. Overlaying the body instead would cover
        // the last row of a list and sit under the pill's shadow.
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UpdateBannerSlot(
              // Dismissing lasts the session, not the build: the state lives
              // here so switching tabs cannot resurrect the banner, and a fresh
              // launch brings it back.
              onOpenSettings: () => _openUpdateSettings(context),
            ),
            HarborNavBar(
              selectedIndex: tabIndex,
              onSelected: (index) => context.read<AppState>().setTab(index),
            ),
          ],
        ),
      ),
    );
  }

  /// Jumps to Settings and asks the screen to bring the updates panel into
  /// view, so "Update now" lands on the control rather than the top of a long
  /// settings list.
  void _openUpdateSettings(BuildContext context) {
    final app = context.read<AppState>();
    app.setTab(5);
    app.requestUpdatesScroll();
  }
}

/// Bottom navigation: a floating pill.
///
/// Design source: https://21st.dev/@arunachalam/components/bottom-nav-bar
///
/// The geometry is measured from that component's live preview in a browser
/// rather than eyeballed: pill height 52, item height 40, fully rounded ends,
/// 8px item padding, a translucent wash on the active tab, and a label that is
/// present ONLY while its tab is active.
///
/// Two deliberate departures, both forced by having six tabs:
///
///  * The pill fills the available width and the active tab is WIDER than the
///    rest. The reference is content-sized, and with six labelled tabs that
///    overflowed every width measured - 384px of pill inside 373dp of space at
///    393dp, and it clipped "SETTINGS" to "SETTING".
///  * The active tab's extra width is measured from the actual label and
///    animated, so switching tabs slides the highlight instead of snapping, and
///    the label can never be wider than the space reserved for it.
///
/// Replaces the previous flat white bar (six equal icon+label columns). The
/// active-only label is the reference's behaviour, so the inactive tabs no
/// longer show text.
class HarborNavBar extends StatelessWidget {
  const HarborNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Reference tokens. `p-2`/`space-x-1` are tightened from 8/4 to 5/2 to pay
  /// for the sixth tab; the pill's height, item height and radius are as-is.
  static const double pillHeight = 52;
  static const double itemHeight = 40;
  static const double pillPad = 5;
  static const double gap = 2;
  static const double radius = 999;
  static const double iconSize = 22;
  static const double labelSize = 10.5;
  static const double labelGap = 6;

  /// `primary/10` in the reference; cobalt at 10% over the white pill.
  static const Color wash = Color(0x1A2347F5);

  /// No explicit `height`: forcing the line box to 1.0 x fontSize clips Sora's
  /// caps, which sit taller than the nominal size, and the label was shaved top
  /// and bottom inside the 40px item.
  static const _labelStyle = TextStyle(
    fontFamily: 'Sora',
    fontSize: labelSize,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
  );

  static const _items = <({IconData icon, String label})>[
    (icon: HarborIcons.radar, label: 'RADAR'),
    (icon: HarborIcons.chartLineUp, label: 'SIGNAL'),
    (icon: HarborIcons.layers, label: 'SOURCES'),
    (icon: HarborIcons.clock, label: 'HISTORY'),
    (icon: HarborIcons.calendar, label: 'EVENTS'),
    (icon: HarborIcons.settingsSliders, label: 'SETTINGS'),
  ];

  /// Intrinsic width of a label, so the active slot can be sized to fit it.
  static double measureLabel(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final active = _items[selectedIndex];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        // The pill floats clear of the gesture bar rather than sitting on it.
        bottomInset > 0 ? bottomInset + 6 : 14,
      ),
      child: Container(
        height: pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: pillPad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: harborLine),
          boxShadow: const [
            // shadow-xl, expressed as the two shadows Tailwind emits.
            BoxShadow(
              color: Color(0x1A0D1526),
              blurRadius: 25,
              offset: Offset(0, 20),
              spreadRadius: -5,
            ),
            BoxShadow(
              color: Color(0x1A0D1526),
              blurRadius: 10,
              offset: Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final avail = constraints.maxWidth -
                gap * (_items.length - 1);
            final target = measureLabel(active.label) + labelGap;

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: target),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, extra, _) {
                // The active tab's slot is one `extra` wider than the rest; the
                // remaining width is shared equally.
                final unit = (avail - extra) / _items.length;
                return Row(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        key: ValueKey('nav-${_items[i].label}'),
                        width: unit + (i == selectedIndex ? extra : 0),
                        child: _PillNavItem(
                          icon: _items[i].icon,
                          label: _items[i].label,
                          isActive: i == selectedIndex,
                          // 0->1 as the slot widens, so the label fades in
                          // instead of appearing already clipped.
                          reveal: target == 0
                              ? 0
                              : (extra / target).clamp(0.0, 1.0),
                          onTap: () => onSelected(i),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.reveal,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final double reveal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? harborCobalt : navIdle;
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: Material(
        color: isActive ? HarborNavBar.wash : Colors.transparent,
        borderRadius: BorderRadius.circular(HarborNavBar.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HarborNavBar.radius),
          child: SizedBox(
            height: HarborNavBar.itemHeight,
            child: Stack(
              // `center`, NOT `centerLeft`: the icon+label pair must sit in the
              // middle of the tab. Aligning left was tempting so the label would
              // clip on the right while the slot animates, but it left the whole
              // group hugging the leading edge - visibly off-centre in the wide
              // active slot. The fade covers the brief symmetric clip instead.
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  // Explicit: the default is centre, but the label's own line
                  // height must not be allowed to shift the pair off-axis.
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, size: HarborNavBar.iconSize, color: color),
                    if (isActive)
                      Flexible(
                        // Flexible, not a bare Padding: while the slot animates
                        // from narrow to wide the label is briefly wider than
                        // the space allowed for it. A `min` Row lays children out
                        // at their intrinsic size and reports RenderFlex
                        // overflow regardless of the surrounding ClipRect -
                        // clipping only stops the paint, not the assertion.
                        // Flexible lets the text take what is actually there.
                        child: ClipRect(
                          child: Opacity(
                            opacity: reveal,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: HarborNavBar.labelGap,
                              ),
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: HarborNavBar._labelStyle
                                    .copyWith(color: color),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
