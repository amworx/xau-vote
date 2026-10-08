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
import 'package:xau_core/xau_core.dart' show RegimeParams;
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
    _restoreIndicators(p);
  }

  /// Fire-and-forget write. Never blocks the UI or throws.
  void _persist(String key, Object value) {
    final p = _prefs;
    if (p == null) return;
    // ignore: discarded_futures
    switch (value) {
      case final bool v:
        p.setBool(key, v);
      case final int v:
        p.setInt(key, v);
      case final double v:
        p.setDouble(key, v);
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

  // Indicator display settings (mockup 13R). Toggles hide tiles; parameters
  // reshape the readings. Display ONLY — consensus math, guard and validation
  // never read these. Persisted like every other preference.
  static const _kInd = {
    'direction': 'ind_direction',
    'adx': 'ind_adx',
    'rsi': 'ind_rsi',
    'macd': 'ind_macd',
    'vwap': 'ind_vwap',
    'atr': 'ind_atr',
    'sentiment': 'ind_sentiment',
    'emaFast': 'ind_ema_fast',
    'emaMid': 'ind_ema_mid',
    'emaTrend': 'ind_ema_trend',
    'swings': 'ind_swings',
    'adxPeriod': 'ind_adx_period',
    'adxStrong': 'ind_adx_strong',
    'rsiPeriod': 'ind_rsi_period',
    'rsiOb': 'ind_rsi_ob',
    'rsiOs': 'ind_rsi_os',
    'macdFast': 'ind_macd_fast',
    'macdSlow': 'ind_macd_slow',
    'macdSignal': 'ind_macd_signal',
    'actLookback': 'ind_act_lookback',
    'atrPeriod': 'ind_atr_period',
  };

  bool _indDirection = true;
  bool _indAdx = true;
  bool _indRsi = true;
  bool _indMacd = true;
  bool _indVwap = true;
  bool _indAtr = true;
  bool _indSentiment = true;

  int _emaFast = 20;
  int _emaMid = 50;
  int _emaTrend = 200;
  int _swings = 5;
  int _adxPeriod = 14;
  double _adxStrong = 25;
  int _rsiPeriod = 14;
  double _rsiOb = 70;
  double _rsiOs = 30;
  int _macdFast = 12;
  int _macdSlow = 26;
  int _macdSignal = 9;
  int _actLookback = 20;
  int _atrPeriod = 14;

  bool get indDirection => _indDirection;
  bool get indAdx => _indAdx;
  bool get indRsi => _indRsi;
  bool get indMacd => _indMacd;
  bool get indVwap => _indVwap;
  bool get indAtr => _indAtr;
  bool get indSentiment => _indSentiment;

  int get emaFast => _emaFast;
  int get emaMid => _emaMid;
  int get emaTrend => _emaTrend;
  int get swings => _swings;
  int get adxPeriod => _adxPeriod;
  double get adxStrong => _adxStrong;
  int get rsiPeriod => _rsiPeriod;
  double get rsiOb => _rsiOb;
  double get rsiOs => _rsiOs;
  int get macdFast => _macdFast;
  int get macdSlow => _macdSlow;
  int get macdSignal => _macdSignal;
  int get actLookback => _actLookback;
  int get atrPeriod => _atrPeriod;

  void _setIndBool(String key, bool v, void Function(bool) apply) {
    apply(v);
    _persist(key, v);
    notifyListeners();
  }

  void setIndDirection(bool v) => _setIndBool(_kInd['direction']!, v, (x) => _indDirection = x);
  void setIndAdx(bool v) => _setIndBool(_kInd['adx']!, v, (x) => _indAdx = x);
  void setIndRsi(bool v) => _setIndBool(_kInd['rsi']!, v, (x) => _indRsi = x);
  void setIndMacd(bool v) => _setIndBool(_kInd['macd']!, v, (x) => _indMacd = x);
  void setIndVwap(bool v) => _setIndBool(_kInd['vwap']!, v, (x) => _indVwap = x);
  void setIndAtr(bool v) => _setIndBool(_kInd['atr']!, v, (x) => _indAtr = x);
  void setIndSentiment(bool v) => _setIndBool(_kInd['sentiment']!, v, (x) => _indSentiment = x);

  void _setIndNum<T extends num>(String key, T v, void Function(T) apply) {
    apply(v);
    _persist(key, v);
    notifyListeners();
  }

  void setEmaFast(int v) => _setIndNum(_kInd['emaFast']!, v, (x) => _emaFast = x);
  void setEmaMid(int v) => _setIndNum(_kInd['emaMid']!, v, (x) => _emaMid = x);
  void setEmaTrend(int v) => _setIndNum(_kInd['emaTrend']!, v, (x) => _emaTrend = x);
  void setSwings(int v) => _setIndNum(_kInd['swings']!, v, (x) => _swings = x);
  void setAdxPeriod(int v) => _setIndNum(_kInd['adxPeriod']!, v, (x) => _adxPeriod = x);
  void setAdxStrong(double v) => _setIndNum(_kInd['adxStrong']!, v, (x) => _adxStrong = x);
  void setRsiPeriod(int v) => _setIndNum(_kInd['rsiPeriod']!, v, (x) => _rsiPeriod = x);
  void setRsiOb(double v) => _setIndNum(_kInd['rsiOb']!, v, (x) => _rsiOb = x);
  void setRsiOs(double v) => _setIndNum(_kInd['rsiOs']!, v, (x) => _rsiOs = x);
  void setMacdFast(int v) => _setIndNum(_kInd['macdFast']!, v, (x) => _macdFast = x);
  void setMacdSlow(int v) => _setIndNum(_kInd['macdSlow']!, v, (x) => _macdSlow = x);
  void setMacdSignal(int v) => _setIndNum(_kInd['macdSignal']!, v, (x) => _macdSignal = x);
  void setActLookback(int v) => _setIndNum(_kInd['actLookback']!, v, (x) => _actLookback = x);
  void setAtrPeriod(int v) => _setIndNum(_kInd['atrPeriod']!, v, (x) => _atrPeriod = x);

  /// Defaults from the approved mockup. The RSI lean bands (65/35) are engine
  /// constants, not user params: a lean is narrower than the OB/OS markers
  /// by design, and exposing both would invite reading them as one setting.
  void resetIndicatorDefaults() {
    _indDirection = true;
    _indAdx = true;
    _indRsi = true;
    _indMacd = true;
    _indVwap = true;
    _indAtr = true;
    _indSentiment = true;
    _emaFast = 20;
    _emaMid = 50;
    _emaTrend = 200;
    _swings = 5;
    _adxPeriod = 14;
    _adxStrong = 25;
    _rsiPeriod = 14;
    _rsiOb = 70;
    _rsiOs = 30;
    _macdFast = 12;
    _macdSlow = 26;
    _macdSignal = 9;
    _actLookback = 20;
    _atrPeriod = 14;
    final p = _prefs;
    if (p != null) {
      for (final e in {
        'direction': true, 'adx': true, 'rsi': true, 'macd': true,
        'vwap': true, 'atr': true, 'sentiment': true,
      }.entries) {
        p.setBool(_kInd[e.key]!, e.value);
      }
      p.setInt(_kInd['emaFast']!, 20);
      p.setInt(_kInd['emaMid']!, 50);
      p.setInt(_kInd['emaTrend']!, 200);
      p.setInt(_kInd['swings']!, 5);
      p.setInt(_kInd['adxPeriod']!, 14);
      p.setDouble(_kInd['adxStrong']!, 25);
      p.setInt(_kInd['rsiPeriod']!, 14);
      p.setDouble(_kInd['rsiOb']!, 70);
      p.setDouble(_kInd['rsiOs']!, 30);
      p.setInt(_kInd['macdFast']!, 12);
      p.setInt(_kInd['macdSlow']!, 26);
      p.setInt(_kInd['macdSignal']!, 9);
      p.setInt(_kInd['actLookback']!, 20);
      p.setInt(_kInd['atrPeriod']!, 14);
    }
    notifyListeners();
  }

  /// Engine params from the indicator settings. RSI lean bands stay at their
  /// engine defaults (65/35): the lean is deliberately narrower than the
  /// user's OB/OS markers.
  RegimeParams toRegimeParams() => RegimeParams(
        emaFast: _emaFast,
        emaMid: _emaMid,
        emaTrend: _emaTrend,
        swingLookback: _swings,
        adxPeriod: _adxPeriod,
        adxStrong: _adxStrong,
        rsiPeriod: _rsiPeriod,
        macdFast: _macdFast,
        macdSlow: _macdSlow,
        macdSignal: _macdSignal,
        atrPeriod: _atrPeriod,
        activityLookback: _actLookback,
      );

  void _restoreIndicators(SharedPreferences p) {
    bool b(String k, bool d) => p.getBool(_kInd[k]!) ?? d;
    int i(String k, int d) => p.getInt(_kInd[k]!) ?? d;
    double f(String k, double d) => p.getDouble(_kInd[k]!) ?? d;
    _indDirection = b('direction', true);
    _indAdx = b('adx', true);
    _indRsi = b('rsi', true);
    _indMacd = b('macd', true);
    _indVwap = b('vwap', true);
    _indAtr = b('atr', true);
    _indSentiment = b('sentiment', true);
    _emaFast = i('emaFast', 20);
    _emaMid = i('emaMid', 50);
    _emaTrend = i('emaTrend', 200);
    _swings = i('swings', 5);
    _adxPeriod = i('adxPeriod', 14);
    _adxStrong = f('adxStrong', 25);
    _rsiPeriod = i('rsiPeriod', 14);
    _rsiOb = f('rsiOb', 70);
    _rsiOs = f('rsiOs', 30);
    _macdFast = i('macdFast', 12);
    _macdSlow = i('macdSlow', 26);
    _macdSignal = i('macdSignal', 9);
    _actLookback = i('actLookback', 20);
    _atrPeriod = i('atrPeriod', 14);
  }

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

  int _updatesScrollRequest = 0;

  /// Increments whenever something asks the Settings screen to reveal the App
  /// updates panel. A counter rather than a bool so two requests in a row both
  /// register.
  int get updatesScrollRequest => _updatesScrollRequest;

  /// Asks the Settings screen to bring the updates panel into view.
  ///
  /// Always notifies, unlike [setTab]: the trader may already be on Settings,
  /// and tapping the banner's "Update now" must still scroll them to the
  /// control rather than doing nothing because the tab did not change.
  void requestUpdatesScroll() {
    _updatesScrollRequest++;
    notifyListeners();
  }

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
