/// In-memory app state (provider). Chosen over Riverpod for MVP
/// simplicity: a single [AppState] ChangeNotifier covers tab routing,
/// mock-scenario previews, target selection, source toggles, and Settings.
/// Persisted to Supabase user preferences in the live phase (T5.7 stub in
/// [BackendService]); for now everything is in-memory per the brief.
library;

import 'package:flutter/foundation.dart';

import '../models/display_models.dart';

/// Radar preview scenarios available in MOCK_MODE.
enum RadarScenario { strong, noConsensus, developing, blackout }

/// Global UI + preference state.
class AppState extends ChangeNotifier {
  int _tabIndex = 0;
  RadarScenario _scenario = RadarScenario.strong;
  TargetSelection _targets = TargetSelection.all;

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
    if (targets == _targets) return;
    _targets = targets;
    notifyListeners();
  }

  void setSourceEnabled(String id, bool enabled) {
    if (_sourceEnabled[id] == enabled) return;
    _sourceEnabled[id] = enabled;
    notifyListeners();
  }

  void setNotifyConsensus(bool value) {
    if (value == _notifyConsensus) return;
    _notifyConsensus = value;
    notifyListeners();
  }

  void setNotifyEntry(bool value) {
    if (value == _notifyEntry) return;
    _notifyEntry = value;
    notifyListeners();
  }

  void setNotifyConfirmation(bool value) {
    if (value == _notifyConfirmation) return;
    _notifyConfirmation = value;
    notifyListeners();
  }

  void setNotifyTargets(bool value) {
    if (value == _notifyTargets) return;
    _notifyTargets = value;
    notifyListeners();
  }

  void setNotifyEvent60(bool value) {
    if (value == _notifyEvent60) return;
    _notifyEvent60 = value;
    notifyListeners();
  }

  void setNotifyEvent15(bool value) {
    if (value == _notifyEvent15) return;
    _notifyEvent15 = value;
    notifyListeners();
  }

  void setNotifySurprises(bool value) {
    if (value == _notifySurprises) return;
    _notifySurprises = value;
    notifyListeners();
  }

  void setNotifyNewsSpikes(bool value) {
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
