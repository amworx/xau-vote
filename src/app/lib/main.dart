/// XAU Radar — free, mobile-first day-trading assistant for XAUUSD.
///
/// Harbor light-first theme, 6 screens (Radar · Signal · Sources ·
/// History · Settings · Events) behind a bottom nav, provider state,
/// MOCK_MODE fixtures by default. See README.md for scope and live-wire stubs.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Guarded: returns immediately in MOCK_MODE (zero config required).
  await BackendService.init();
  runApp(const XauRadarApp());
}

/// Root widget. Owns the [AppState] provider so the widget tree (and widget
/// tests pumping [XauRadarApp] directly) always has state available.
/// Asserts MOCK_MODE so release builds never silently ship fixtures as
/// live data (flip the flag deliberately for T5.7).
class XauRadarApp extends StatelessWidget {
  const XauRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    assert(mockMode == true, 'Live mode is not wired yet (T5.7).');
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const _Shell(),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  static const _screens = [
    RadarScreen(),
    SignalScreen(),
    SourcesScreen(),
    HistoryScreen(),
    SettingsScreen(),
    EventsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tabIndex = context.watch<AppState>().tabIndex;
    return MaterialApp(
      title: 'XAU Radar',
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
          child: _screens[tabIndex],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tabIndex,
          onDestinationSelected: (index) =>
              context.read<AppState>().setTab(index),
          destinations: const [
            NavigationDestination(
              icon: Icon(HarborIcons.radar, size: 20),
              label: 'RADAR',
            ),
            NavigationDestination(
              icon: Icon(HarborIcons.chartLineUp, size: 20),
              label: 'SIGNAL',
            ),
            NavigationDestination(
              icon: Icon(HarborIcons.layers, size: 20),
              label: 'SOURCES',
            ),
            NavigationDestination(
              icon: Icon(HarborIcons.clock, size: 20),
              label: 'HISTORY',
            ),
            NavigationDestination(
              icon: Icon(HarborIcons.settingsSliders, size: 20),
              label: 'CONFIG',
            ),
            NavigationDestination(
              icon: Icon(HarborIcons.calendar, size: 20),
              label: 'EVENTS',
            ),
          ],
        ),
      ),
    );
  }
}
