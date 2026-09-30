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
