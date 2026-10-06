/// Screen 5 — Settings (spec §24 controls).
///
/// Fixed timeframe display (15M/5M/1H), pip convention, target selection and
/// notification toggles. Persisted in-memory via [AppState] for the MVP;
/// Supabase user preferences arrive with live wiring (T5.7).
///
/// Restyled onto the unified Harbor language: [HarborEyebrow] group headings
/// on a [HarborCard] container, [HarborDivider] between rows, Sora titles and
/// subtitles, Space Mono values, and [HarborPill] for every selector. A toggle
/// track reads [harborLine] off and [harborLong] on, because every switch here
/// gates participation or alerting — never a direction — and the thumb is a
/// constant white so only the track carries the state.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/display_models.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';
import '../widgets/skeleton.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _scroll = ScrollController();

  /// Last handled request, so the jump runs once per request rather than on
  /// every unrelated rebuild.
  int _handledScrollRequest = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the App updates panel into view when the banner asks for it.
  ///
  /// Deferred to the end of the frame because the request usually arrives in
  /// the same build that switches to this tab, before the list has been laid
  /// out and therefore has no scroll extent to animate against.
  void _maybeScrollToUpdates(AppState state) {
    if (state.updatesScrollRequest == _handledScrollRequest) return;
    _handledScrollRequest = state.updatesScrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (_scroll.position.maxScrollExtent * 0.82).clamp(
        0.0,
        double.infinity,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _maybeScrollToUpdates(state);
    return ListView(
      controller: _scroll,
      key: const PageStorageKey<String>('settings'),
      // Horizontal gutters belong to the shared chrome (header 18px, cards
      // 18px), so the list itself only owns the trailing space.
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        // Matches the bottom-nav label: one name for the tab, whatever is on
        // screen (D-20260929-004).
        const HarborHeader(subtitle: 'SETTINGS'),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
          child: HarborEyebrow('Control panel'),
        ),
        const SizedBox(height: 12),
        const _Group(
          title: 'Timeframes',
          children: [
            _SettingRow(
              title: 'Signal / Confirm / Context',
              subtitle: 'Fixed by product spec',
              value: '15M / 5M / 1H',
            ),
            _SettingRow(
              title: 'Default view',
              subtitle: 'Screen shown on launch',
              value: 'RADAR',
            ),
          ],
        ),
        const _Group(
          title: 'Targets',
          children: [_TargetPills()],
        ),
        const _Group(
          title: 'Display',
          children: [_PipConventionPills()],
        ),
        _Group(
          title: 'Notifications · signals',
          children: [
            // Permission is requested here, in context, rather than on cold
            // launch: the trader is turning alerts on, which is exactly when the
            // prompt means something.
            const _NotificationPermission(),
            _ToggleRow(
              title: 'Consensus forming',
              subtitle: 'Developing to ready transitions',
              value: state.notifyConsensus,
              onChanged: _askThen(
                context,
                state.notifyConsensus,
                state.setNotifyConsensus,
              ),
            ),
            _ToggleRow(
              title: 'Entry approaching',
              subtitle: 'Price enters the zone',
              value: state.notifyEntry,
              onChanged: state.setNotifyEntry,
            ),
            _ToggleRow(
              title: 'Confirmation',
              subtitle: '5M confirms the setup',
              value: state.notifyConfirmation,
              onChanged: state.setNotifyConfirmation,
            ),
            const _ToggleRow(
              title: 'Invalidation',
              subtitle: 'Setup fails, always on',
              value: true,
              onChanged: null,
            ),
            _ToggleRow(
              title: 'Targets hit',
              subtitle: 'TP1 / TP2 / TP3',
              value: state.notifyTargets,
              onChanged: state.setNotifyTargets,
            ),
          ],
        ),
        _Group(
          title: 'Events · context only',
          children: [
            _SettingRow(
              title: 'Blackout before HIGH event',
              subtitle: 'No new signals in this window',
              value: '${state.blackoutBeforeMin} min',
            ),
            _SettingRow(
              title: 'Blackout after HIGH event',
              subtitle: 'Resume scan after release',
              value: '${state.blackoutAfterMin} min',
            ),
            _ToggleRow(
              title: '60-min warning',
              subtitle: 'HIGH event approaching',
              value: state.notifyEvent60,
              onChanged: state.setNotifyEvent60,
            ),
            _ToggleRow(
              title: '15-min warning',
              subtitle: 'Blackout about to start',
              value: state.notifyEvent15,
              onChanged: state.setNotifyEvent15,
            ),
            _ToggleRow(
              title: 'Surprises',
              subtitle: 'Actual vs forecast gaps',
              value: state.notifySurprises,
              onChanged: state.setNotifySurprises,
            ),
            _ToggleRow(
              title: 'News spikes',
              subtitle: 'Unusual gold-news volume',
              value: state.notifyNewsSpikes,
              onChanged: state.setNotifyNewsSpikes,
            ),
          ],
        ),
        const _Group(
          title: 'About',
          children: [
            _SettingRow(
              title: 'Developer',
              subtitle: 'Built by',
              value: 'AMWORX',
            ),
            _SettingRow(
              title: 'App',
              subtitle: 'XAUUSD 15M consensus assistant',
              value: 'XV',
            ),
          ],
        ),
        const _UpdateGroup(),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        // Display-only micro-copy. The pip convention note, the icon
        // attribution and the not-financial-advice line are all required:
        // the UIcons licence demands attribution and the app must not read as
        // a recommendation. The pip figure follows the selected convention.
        _Micro(text: 'Pip x${state.pipConvention.pipSizeLabel} · per D-003 · v0.1 MVP'),
        const _Micro(text: 'UIcons by Flaticon'),
        const _Micro(text: 'Not financial advice · never executes trades'),
      ],
    );
  }
}

/// Card container for one settings group: an [HarborEyebrow] heading and
/// hairline-separated rows (mockup `.group` / `.srow`).
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: HarborCard(
        margin: 0,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
              child: HarborEyebrow(title, color: harborCobalt),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const HarborDivider(),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// In-app updater (Settings → Updates).
///
/// Owns its own [UpdateService] so a rebuild cannot interrupt a download, and
/// disposes it on teardown. Every control is derived from [UpdateState] rather
/// than local flags, so the UI cannot show "downloading" after a cancel or offer
/// an install for a file that failed its checksum.
///
/// The controls deliberately stop short of installing silently: Android
/// requires the user to approve the install, and the button says so.
class _UpdateGroup extends StatelessWidget {
  const _UpdateGroup();

  @override
  Widget build(BuildContext context) {
    // The service is provided at the app root rather than created here. It used
    // to be built inside this State, which meant the update banner and this
    // panel each drove a SEPARATE UpdateService: a download started in one was
    // invisible to the other, and "one download path" was only ever true in
    // principle. Reading the shared instance keeps a single source of truth.
    final service = context.watch<UpdateService?>();

    if (service == null) {
      // No endpoint was supplied at build time. Say so instead of offering a
      // check that cannot succeed.
      return const _Group(
        title: 'App updates',
        children: [
          _SettingRow(
            title: 'Check for updates',
            subtitle: 'No update endpoint in this build',
            value: 'UNAVAILABLE',
          ),
        ],
      );
    }

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.state;
        return _Group(
          title: 'App updates',
          children: [
            _UpdateStatus(state: state, service: service),
            // `available` MUST be included. It is the one state where the user
            // has just been told a new version exists and can do nothing about
            // it: the controls used to render only while a download was already
            // active, so DOWNLOAD never appeared and the updater could check but
            // never download or install.
            if (state.status == DownloadState.available ||
                state.isActive ||
                state.status == DownloadState.ready)
              _UpdateControls(
                state: state,
                service: service,
                // Install failures surface as a SnackBar from the button that
                // triggered them, so there is no failure string to hold here.
                installFailure: null,
              ),
          ],
        );
      },
    );
  }
}

/// Status line plus, while downloading, a progress bar.
class _UpdateStatus extends StatelessWidget {
  const _UpdateStatus({required this.state, required this.service});

  final UpdateState state;
  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final release = state.release;
    final detail = switch (state.status) {
      DownloadState.idle =>
        'Compares against the installed build',
      DownloadState.checking =>
        'Contacting the update endpoint...',
      DownloadState.upToDate => state.message ?? 'Up to date',
      DownloadState.available =>
        '${release?.version ?? 'Update'} available${_sizeNote(release)}',
      DownloadState.downloading => 'Downloading...',
      DownloadState.paused => state.message ?? 'Paused',
      DownloadState.verifying => 'Verifying signature...',
      DownloadState.ready => state.message ?? 'Ready to install',
      DownloadState.failed => state.message ?? 'Update failed',
    };

    final label = switch (state.status) {
      DownloadState.available ||
      DownloadState.upToDate ||
      DownloadState.failed =>
        'Check for updates',
      DownloadState.ready => 'Update downloaded',
      _ => 'Update in progress',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _RowLabels(label, detail)),
              const SizedBox(width: 10),
              if (!state.isBusy && !state.isInstallable)
                TextButton(
                  onPressed: () => service.check(),
                  style: TextButton.styleFrom(
                    foregroundColor: harborCobalt,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'CHECK',
                    style: TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ],
          ),
          if (state.isActive) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 4,
                backgroundColor: harborLine,
                valueColor: const AlwaysStoppedAnimation(harborCobalt),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _bytes(state.received),
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 9,
                color: harborFaint,
              ),
            ),
          ],
          if (state.status == DownloadState.ready)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Android will ask you to approve the install.',
                style: TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 9,
                  color: harborFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _sizeNote(ReleaseInfo? r) =>
      (r != null && r.sizeBytes > 0) ? ' · ${_bytes(r.sizeBytes)}' : '';

  static String _bytes(int n) {
    if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '$n B';
  }
}

/// Action row: download / pause / resume / cancel / install.
class _UpdateControls extends StatelessWidget {
  const _UpdateControls({
    required this.state,
    required this.service,
    required this.installFailure,
  });

  final UpdateState state;
  final UpdateService service;
  final String? installFailure;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];

    if (state.status == DownloadState.available) {
      actions.add(_action('DOWNLOAD', () => service.startDownload()));
    }
    if (state.status == DownloadState.downloading) {
      actions.add(_action('PAUSE', () => service.pause()));
    }
    if (state.status == DownloadState.paused) {
      actions.add(_action('RESUME', () => service.startDownload()));
    }
    if (state.isActive) {
      actions.add(_action('CANCEL', () => service.cancel(), warn: true));
    }
    if (state.isInstallable) {
      actions.add(_action('INSTALL', () => _install(context)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Wrap(spacing: 7, runSpacing: 7, children: actions),
    );
  }

  /// One outline action, in the app's pill language.
  /// Installs the verified update, asking Android for the grant first if needed.
  ///
  /// `REQUEST_INSTALL_PACKAGES` is not granted at install time: from Android 8
  /// the user grants it per-source in Settings, and `checkSelfPermission` keeps
  /// reporting GRANTED regardless, so the real question is
  /// `canRequestPackageInstalls()`. When that is false the app offers to open
  /// that screen. Previously it only *named* the setting in a snackbar and left
  /// the user to find it, which is what made the update look uninstallable.
  ///
  /// A null answer means the platform could not tell us, which is not the same
  /// as a refusal — the install is attempted either way, so nothing is blocked
  /// by a missing capability rather than a missing grant.
  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (await service.canInstallPackages() == false) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Android needs your permission to install this update.',
          ),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'ALLOW',
            onPressed: service.requestInstallPermission,
          ),
        ),
      );
      return;
    }

    final result = await service.install();
    if (!context.mounted || result.ok) return;

    final message = switch (result.outcome) {
      InstallOutcome.needsPermission =>
        'Still not permitted. Turn on "Install unknown apps" for XV, then '
            'tap INSTALL again.',
      InstallOutcome.missingFile =>
        'The downloaded update is missing. Tap DOWNLOAD again.',
      InstallOutcome.failed =>
        'Could not open the installer'
            '${result.detail == null ? '' : ': ${result.detail}'}.',
      InstallOutcome.opened => '',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _action(String label, VoidCallback onTap, {bool warn = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: warn ? harborWarn : harborCobalt),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: warn ? harborWarn : harborCobalt,
          ),
        ),
      ),
    );
  }
}

/// Wraps a notification toggle so switching it ON asks for OS permission.
///
/// The toggle still flips either way: denying the permission must not stop the
/// trader recording which alerts they want, and the row below explains that
/// alerts cannot arrive until the permission is granted.
ValueChanged<bool> _askThen(BuildContext context, bool current, ValueChanged<bool> set) {
  return (value) {
    set(value);
    // Only ask when turning on; re-prompting on every switch would be nagging.
    if (value && !current) _NotificationPermission.request(context);
  };
}

/// Notification permission row and the request action.
///
/// Reports the real state rather than assuming: granted, not granted, or
/// unavailable because this build has no Firebase configuration.
class _NotificationPermission extends StatefulWidget {
  const _NotificationPermission();

  /// Asks for permission from the nearest context.
  static Future<void> request(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final service = Provider.of<NotificationService?>(
      context,
      listen: false,
    ) ?? NotificationService();
    final granted = await service.request();
    if (!granted) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications stay off. Alerts need permission — enable them in '
            'Android Settings › Apps › XV › Notifications.',
          ),
        ),
      );
    }
  }

  @override
  State<_NotificationPermission> createState() => _NotificationPermissionState();
}

class _NotificationPermissionState extends State<_NotificationPermission> {
  NotificationService? _service;
  bool _granted = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    final provided = Provider.of<NotificationService?>(context, listen: false);
    _service = provided ?? NotificationService();
    _read();
  }

  Future<void> _read() async {
    final service = _service ?? NotificationService();
    final granted = await service.isGranted();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canDeliver = _service?.canDeliver ?? false;
    // The permission read is asynchronous; hold the row rather than showing a
    // wrong "OFF" for a frame.
    if (!_checked) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SkeletonBox(height: 26, radius: 8),
      );
    }
    return _SettingRow(
      title: 'Allow notifications',
      subtitle: canDeliver
          ? 'Alerts can be delivered'
          : 'Permission granted — delivery not yet enabled',
      value: _granted ? 'ON' : 'OFF',
    );
  }
}

/// Read-only row: Sora title, Sora dim subtitle, Space Mono value.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(child: _RowLabels(title, subtitle)),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Title + subtitle block shared by the read-only and toggle rows.
class _RowLabels extends StatelessWidget {
  const _RowLabels(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: harborInk,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 10.5,
            color: harborDim,
          ),
        ),
      ],
    );
  }
}

/// Target-scope selector (spec §10). [HarborPill] is the same control the
/// Radar card and the Signal screen use, so one selection is mirrored on all
/// three: it writes straight to [AppState.targets] and narrows the visible
/// targets everywhere it is read.
class _TargetPills extends StatelessWidget {
  const _TargetPills();

  static const _options = [
    (label: 'TP1 + TP2 + TP3', value: TargetSelection.all),
    (label: 'TP1 + TP2', value: TargetSelection.tp1Tp2),
    (label: 'TP1 ONLY', value: TargetSelection.tp1Only),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in _options)
            HarborPill(
              option.label,
              fontSize: 10,
              active: state.targets == option.value,
              onTap: () => state.setTargets(option.value),
            ),
        ],
      ),
    );
  }
}

/// Pip-size selector (D-20260927-003), in its own DISPLAY group.
///
/// Same [HarborPill] language as every other selector in the app, active
/// cobalt. The labels state the convention itself (`A · 0.10` / `B · 0.01`)
/// because "pip size" alone is ambiguous, and the subtitle promises the one
/// thing the setting may do: rescale pip readouts, never a price, a level or
/// an R:R. Convention B is the default (the user trades FXPro/Vantage).
class _PipConventionPills extends StatelessWidget {
  const _PipConventionPills();

  static const _options = [
    (value: PipConvention.a, label: 'A · 0.10'),
    (value: PipConvention.b, label: 'B · 0.01'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RowLabels(
            'Pip size',
            'Display unit only · prices and levels never change',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in _options)
                HarborPill(
                  option.label,
                  fontSize: 10,
                  active: state.pipConvention == option.value,
                  onTap: () => state.setPipConvention(option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Toggle row. Off track is [harborLine], on track [harborLong]: every switch
/// on this screen gates participation or alerting, never a trade direction.
/// A `null` [onChanged] is a safety-critical always-on alert, so it is drawn
/// in the same tokens at reduced weight rather than a Material grey.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Expanded(child: _RowLabels(title, subtitle)),
          const SizedBox(width: 10),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: harborLong,
            inactiveTrackColor: harborLine,
            // The always-on invalidation alert is still a Harbor surface, so it
            // dims through the same tokens instead of a Material grey — but it
            // dims as a GREEN track, not a pale one. It is a safety-critical
            // alert that is permanently on, so it must never render in the
            // OFF palette just because it cannot be tapped.
            trackColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (!states.contains(WidgetState.disabled)) return null;
                return states.contains(WidgetState.selected)
                    ? harborLong.withValues(alpha: 0.45)
                    : harborLine;
              },
            ),
            // The thumb is CONSTANT (white) in both states, so the track alone
            // carries on/off. An OFF thumb in a tinted neutral ([harborFaint]
            // #8FA0B8) painted a blue-grey disc on the [harborLine] track that
            // read as "partially on". White recedes against the pale track and
            // cannot be mistaken for the ON state, which stays unmistakably
            // [harborLong] — the one place green means an active switch.
            thumbColor: const WidgetStatePropertyAll<Color?>(Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Centred mono micro-copy (mockup `.micro`).
class _Micro extends StatelessWidget {
  const _Micro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            letterSpacing: 0.6,
            color: harborFaint,
          ),
        ),
      ),
    );
  }
}
