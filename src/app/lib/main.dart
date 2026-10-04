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
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/pull_to_refresh.dart';

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
        ],
        child: app,
      );
    }
    return app;
  }
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
        bottomNavigationBar: HarborNavBar(
          selectedIndex: tabIndex,
          onSelected: (index) => context.read<AppState>().setTab(index),
        ),
      ),
    );
  }
}

/// Bottom navigation (mockup `.bottom`): 72px white bar, hairline top
/// border, six equal icon+label columns.
///
/// Replaces the Material `NavigationBar`: the mockup has no indicator pill
/// and no background highlight, only a cobalt active colour.
class HarborNavBar extends StatelessWidget {
  const HarborNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double height = 72;

  static const _items = [
    (icon: HarborIcons.radar, label: 'RADAR'),
    (icon: HarborIcons.chartLineUp, label: 'SIGNAL'),
    (icon: HarborIcons.layers, label: 'SOURCES'),
    (icon: HarborIcons.clock, label: 'HISTORY'),
    (icon: HarborIcons.calendar, label: 'EVENTS'),
    (icon: HarborIcons.settingsSliders, label: 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: harborLine)),
      ),
      padding: EdgeInsets.fromLTRB(7, 7, 7, 9 + bottomInset),
      child: SizedBox(
        height: height - 7 - 9,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  icon: _items[i].icon,
                  label: _items[i].label,
                  isActive: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? harborCobalt : navIdle;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 30,
            child: Center(child: Icon(icon, size: 18, color: color)),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
