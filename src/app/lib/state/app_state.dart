/// In-memory app state (provider). Chosen over Riverpod for MVP
/// simplicity: a single [AppState] ChangeNotifier covers tab routing,
/// mock-scenario previews, target selection, source toggles, and Settings.
/// Persisted to Supabase user preferences in the live phase (T5.7 stub in
/// [BackendService]); for now everything is in-memory per the brief.
library;

import 'package:flutter/foundation.dart';

import '../models/display_models.dart';

/// Radar preview scenarios available in MOCK_MODE.
enum RadarScenario { strong, noConsensus, developing }

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

  int get tabIndex => _tabIndex;
  RadarScenario get scenario => _scenario;
  TargetSelection get targets => _targets;
  Map<String, bool> get sourceEnabled => Map.unmodifiable(_sourceEnabled);

  bool get notifyConsensus => _notifyConsensus;
  bool get notifyEntry => _notifyEntry;
  bool get notifyConfirmation => _notifyConfirmation;
  bool get notifyInvalidation => true;
  bool get notifyTargets => _notifyTargets;

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
}
