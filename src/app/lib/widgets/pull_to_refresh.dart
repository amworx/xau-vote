/// Pull-to-refresh, shared by every data-driven screen.
///
/// # Why this exists alongside polling
///
/// The app already polls, but polling cannot help when a poll has been failing
/// (a lost connection, a suspended app, a device waking from sleep) and the
/// screen is showing whatever it last managed to load. A pull-to-refresh gives
/// the trader a way to demand a fresh read on demand, and it is the gesture
/// every mobile user already reaches for.
///
/// The refresh is wired to the same [LiveData.refresh] / [AnalysisService.refresh]
/// the timer uses, so there is exactly one fetch path and no chance of the two
/// disagreeing.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/analysis_service.dart';
import '../data/live_data.dart';

/// Wraps [child] in a [RefreshIndicator] that re-reads the live snapshot.
///
/// Returns [child] untouched in an offline build, which has no poller and
/// therefore nothing to refresh.
Widget withPullToRefresh(BuildContext context, Widget child) {
  LiveData? live;
  try {
    live = context.read<LiveData>();
  } on ProviderNotFoundException {
    // Offline build: fixtures are already in memory, so there is nothing to
    // fetch and a spinner would only imply otherwise.
    return child;
  }
  final snapshot = live;

  // Read the scanner before any await: reaching for the context afterwards is
  // only safe while this widget is still mounted, and a pull can outlive a tab
  // switch. Offline builds have no scanner, which is not an error.
  AnalysisService? scanner;
  try {
    scanner = context.read<AnalysisService>();
  } catch (_) {
    // No scanner provider.
  }

  return RefreshIndicator(
    onRefresh: () async {
      await snapshot.refresh();
      try {
        await scanner?.refresh();
      } catch (_) {
        // The scanner reports its own error on its own card.
      }
    },
    child: child,
  );
}
