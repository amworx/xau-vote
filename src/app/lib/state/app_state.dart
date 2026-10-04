/// Global app state (provider). Chosen over Riverpod for MVP simplicity: a
/// single [AppState] ChangeNotifier covers tab routing, mock-scenario previews,
/// target selection, source toggles, and Settings.
///
/// Preferences are persisted to device storage so a choice survives a restart;
/// session state is not, so a launch never lands in a demo scenario. Supabase
/// user preferences remain a later phase ([BackendService]).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/display_models.dart';

/// Radar preview scenarios available in MOCK_MODE.
enum RadarScenario { strong, noConsensus, developing, blackout }

/// Global UI + preference state.
///
/// # Preferences persist; session state does not
///
/// Anything the trader chooses — target scope, pip convention, alert
/// preferences — is written to device storage, because a setting that silently
/// reverts on restart reads as broken even though the toggle moved. Session
/// state (which tab, which mock scenario) is deliberately NOT persisted: a
/// launch should never drop the trader into a demo state.
///
/// Storage failures are swallowed on purpose. A device that cannot write
/// preferences should still run the app with defaults rather than fail to start.
class AppState extends ChangeNotifier {
  AppState({this.prefs}) : _prefs = prefs {
    _restore();
  }

  /// Injected by tests; the app resolves it in ``load``.
  @visibleForTesting
  final SharedPreferences? prefs;

  SharedPreferences? _prefs;

  static const _kTargets = 'targets';
  static const _kPip = 'pip';
  static const _kNotify = {
    'consensus': 'notify_consensus',
    'entry': 'notify_entry',
    'confirmation': 'notify_confirmation',
    'targets': 'notify_targets',
    'event60': 'notify_event60',
    'event15': 'notify_event15',
    'surprises': 'notify_surprises',
    'news': 'notify_news',
  };

  /// Loads stored preferences. Safe to call once at startup.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _restore();
    } catch (_) {
      // Keep defaults; a storage failure must not stop the app.
    }
    notifyListeners();
  }

  void _restore() {
    final p = _prefs;
    if (p == null) return;
    _targets = TargetSelection.values.firstWhere(
      (t) => t.name == p.getString(_kTargets),
      orElse: () => _targets,
    );
    _pipConvention = PipConvention.values.firstWhere(
      (c) => c.name == p.getString(_kPip),
      orElse: () => _pipConvention,
    );
    _notifyConsensus = p.getBool(_kNotify['consensus']!) ?? _notifyConsensus;
    _notifyEntry = p.getBool(_kNotify['entry']!) ?? _notifyEntry;
    _notifyConfirmation = p.getBool(_kNotify['confirmation']!) ?? _notifyConfirmation;
    _notifyTargets = p.getBool(_kNotify['targets']!) ?? _notifyTargets;
    _notifyEvent60 = p.getBool(_kNotify['event60']!) ?? _notifyEvent60;
    _notifyEvent15 = p.getBool(_kNotify['event15']!) ?? _notifyEvent15;
    _notifySurprises = p.getBool(_kNotify['surprises']!) ?? _notifySurprises;
    _notifyNewsSpikes = p.getBool(_kNotify['news']!) ?? _notifyNewsSpikes;
    for (final entry in _sourceEnabled.entries.toList()) {
      _sourceEnabled[entry.key] = p.getBool('src_${entry.key}') ?? entry.value;
    }
  }

  /// Fire-and-forget write. Never blocks the UI or throws.
  void _persist(String key, Object value) {
    final p = _prefs;
    if (p == null) return;
    // ignore: discarded_futures
    switch (value) {
      case final bool v:
        p.setBool(key, v);
      case final String v:
        p.setString(key, v);
    }
  }

  int _tabIndex = 0;
  RadarScenario _scenario = RadarScenario.strong;
  // TP1 is the default target scope. The trader asked for a single take-profit
  // as the starting position, which is also the conservative reading: TP1 is the
  // nearest level, so it is the one most likely to be reached, and the levels
  // below it stay visible rather than being implied away.
  TargetSelection _targets = TargetSelection.tp1Only;

  // D-20260927-003 — pip size is a display preference. Points stay canonical;
  // the convention only rescales pip figures (default B = 0.01, FXPro/Vantage).
  PipConvention _pipConvention = PipConvention.b;

  final Map<String, bool> _sourceEnabled = {
    'A': true,
    'B': true,
    'C': true,
    'E': true,
    'D': true,
  };

  bool _notifyConsensus = true;
  bool _notifyEntry = true;
  bool _notifyConfirmation = true;
  // Invalidation alerts are safety-critical: always on, not user-toggled.
  bool _notifyTargets = true;

  // TASK-07 — Events settings (addendum §5.3). In-memory for the MVP;
  // blackout windows feed the guard copy in Settings only until T5.7.
  int _blackoutBeforeMin = 30;
  int _blackoutAfterMin = 15;
  bool _notifyEvent60 = true;
  bool _notifyEvent15 = true;
  bool _notifySurprises = true;
  bool _notifyNewsSpikes = false;

  int get tabIndex => _tabIndex;
  RadarScenario get scenario => _scenario;
  TargetSelection get targets => _targets;
  PipConvention get pipConvention => _pipConvention;
  Map<String, bool> get sourceEnabled => Map.unmodifiable(_sourceEnabled);

  bool get notifyConsensus => _notifyConsensus;
  bool get notifyEntry => _notifyEntry;
  bool get notifyConfirmation => _notifyConfirmation;
  bool get notifyInvalidation => true;
  bool get notifyTargets => _notifyTargets;

  int get blackoutBeforeMin => _blackoutBeforeMin;
  int get blackoutAfterMin => _blackoutAfterMin;
  bool get notifyEvent60 => _notifyEvent60;
  bool get notifyEvent15 => _notifyEvent15;
  bool get notifySurprises => _notifySurprises;
  bool get notifyNewsSpikes => _notifyNewsSpikes;

  bool isSourceEnabled(String id) => _sourceEnabled[id] ?? true;

  void setTab(int index) {
    if (index == _tabIndex) return;
    _tabIndex = index;
    notifyListeners();
  }

  void goToSignal() => setTab(1);

  void setScenario(RadarScenario scenario) {
    if (scenario == _scenario) return;
    _scenario = scenario;
    notifyListeners();
  }

  void setTargets(TargetSelection targets) {
    _persist(_kTargets, targets.name);
    if (targets == _targets) return;
    _targets = targets;
    notifyListeners();
  }

  /// Pick the pip size (D-20260927-003). Display-only: no price, level or
  /// R:R is derived from this, so the choice is safe to change at any time.
  void setPipConvention(PipConvention convention) {
    _persist(_kPip, convention.name);
    if (convention == _pipConvention) return;
    _pipConvention = convention;
    notifyListeners();
  }

  void setSourceEnabled(String id, bool enabled) {
    _persist('src_$id', enabled);
    if (_sourceEnabled[id] == enabled) return;
    _sourceEnabled[id] = enabled;
    notifyListeners();
  }

  void setNotifyConsensus(bool value) {
    _persist(_kNotify['consensus']!, value);
    if (value == _notifyConsensus) return;
    _notifyConsensus = value;
    notifyListeners();
  }

  void setNotifyEntry(bool value) {
    _persist(_kNotify['entry']!, value);
    if (value == _notifyEntry) return;
    _notifyEntry = value;
    notifyListeners();
  }

  void setNotifyConfirmation(bool value) {
    _persist(_kNotify['confirmation']!, value);
    if (value == _notifyConfirmation) return;
    _notifyConfirmation = value;
    notifyListeners();
  }

  void setNotifyTargets(bool value) {
    _persist(_kNotify['targets']!, value);
    if (value == _notifyTargets) return;
    _notifyTargets = value;
    notifyListeners();
  }

  void setNotifyEvent60(bool value) {
    _persist(_kNotify['event60']!, value);
    if (value == _notifyEvent60) return;
    _notifyEvent60 = value;
    notifyListeners();
  }

  void setNotifyEvent15(bool value) {
    _persist(_kNotify['event15']!, value);
    if (value == _notifyEvent15) return;
    _notifyEvent15 = value;
    notifyListeners();
  }

  void setNotifySurprises(bool value) {
    _persist(_kNotify['surprises']!, value);
    if (value == _notifySurprises) return;
    _notifySurprises = value;
    notifyListeners();
  }

  void setNotifyNewsSpikes(bool value) {
    _persist(_kNotify['news']!, value);
    if (value == _notifyNewsSpikes) return;
    _notifyNewsSpikes = value;
    notifyListeners();
  }

  /// Blackout windows (addendum §5.3, minutes). Editable stepping arrives
  /// with live Settings persistence (T5.7); setters exist so the fields
  /// stay intentionally mutable.
  void setBlackoutBeforeMin(int value) {
    if (value == _blackoutBeforeMin) return;
    _blackoutBeforeMin = value;
    notifyListeners();
  }

  void setBlackoutAfterMin(int value) {
    if (value == _blackoutAfterMin) return;
    _blackoutAfterMin = value;
    notifyListeners();
  }
}
