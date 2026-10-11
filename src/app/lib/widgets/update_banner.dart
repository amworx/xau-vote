/// The update banner: a dismissible notice that a newer build exists.
///
/// Design source: https://21st.dev/@felipemenezes098/components/banner-04
///
/// Geometry is measured from that component's live preview rather than
/// eyeballed: a 36px circular icon badge at 10% wash with a 20px glyph, a 14px
/// title, 32px buttons at 8px radius, and two actions (a ghost and a filled
/// one) over a `14px 16px` padded card.
///
/// Three departures from the reference, each deliberate:
///
///  * White, not dark. The app is light-only, and a dark banner would be the
///    only dark surface outside the two existing ink accents (Radar's day-move
///    strip, the Events guardrail bar).
///  * 16px radius, the app's card radius, rather than the reference's 10px.
///  * This banner NEVER downloads anything. It is a notice plus a shortcut into
///    Settings, where the downloader lives. Two implementations of one feature
///    is how the original updater bug stayed invisible for so long, so there is
///    deliberately exactly one download path in the app.
///
/// The wording changes once the APK is on disk and verified. Android still
/// requires the user to approve the install, so claiming the update is done
/// would be a lie the user discovers thirty seconds later.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../services/update_service.dart';
import '../theme.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.service,
    required this.dismissed,
    required this.onDismiss,
    required this.onOpenSettings,
  });

  final UpdateService service;

  /// True once the trader has chosen "Later". Held by the caller for the
  /// lifetime of the session, so the banner shows once per session.
  final bool dismissed;

  final VoidCallback onDismiss;
  final VoidCallback onOpenSettings;

  /// Whether the banner has anything to say right now.
  ///
  /// Only [DownloadState.available] and [DownloadState.ready] qualify. A
  /// download already in flight is reported in Settings, and repeating it here
  /// would be noise.
  static bool isRelevant(UpdateState state) =>
      state.status == DownloadState.available ||
      state.status == DownloadState.ready;

  @override
  Widget build(BuildContext context) {
    final state = service.state;
    if (dismissed || !isRelevant(state)) return const SizedBox.shrink();

    final release = state.release;
    if (release == null) return const SizedBox.shrink();

    // "Downloaded, awaiting your approval" rather than "updated".
    final readyToInstall = state.status == DownloadState.ready;
    final title = readyToInstall
        ? '${release.version} downloaded — restart to install'
        : 'Update available — ${release.version}';
    final description = readyToInstall
        ? 'Verified against the published checksum. Android will ask you to '
            'approve the install.'
        : release.notes.trim().isEmpty
            ? 'A newer build is published for this app.'
            : release.notes.trim();
    final size = '${(release.sizeBytes / 1048576).toStringAsFixed(1)} MB';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: harborLine),
          boxShadow: const [
            // Lifted clear of the nav pill below it, so the two read as separate
            // surfaces rather than one thick bar.
            BoxShadow(
              color: Color(0x1F0D1526),
              blurRadius: 24,
              offset: Offset(0, 10),
              spreadRadius: -6,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Badge(readyToInstall: readyToInstall),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: harborInk,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 12.5,
                            height: 1.45,
                            color: harborDim,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          readyToInstall
                              ? 'signed release build · checksum verified'
                              : '$size · signed release build',
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 10,
                            letterSpacing: 0.4,
                            color: harborFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Button(
                    label: 'Later',
                    filled: false,
                    onTap: onDismiss,
                  ),
                  const SizedBox(width: 8),
                  _Button(
                    label: readyToInstall ? 'Install' : 'Update now',
                    filled: true,
                    onTap: onOpenSettings,
                  ),
                  // No trailing version label: the title already carries it,
                  // and a third item here overflowed the row by 21px at 360dp.
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reference's 36px circle at 10% wash. Green once the file is verified and
/// waiting only on the user's approval.
class _Badge extends StatelessWidget {
  const _Badge({required this.readyToInstall});

  final bool readyToInstall;

  @override
  Widget build(BuildContext context) {
    final colour = readyToInstall ? harborLong : harborCobalt;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: readyToInstall
            ? const Color(0x1A0E9F6E)
            : const Color(0x1A2347F5),
      ),
      child: Center(
        child: readyToInstall
            ? Icon(HarborIcons.check, size: 18, color: colour)
            : const _ArrowUpCircle(colour: harborCobalt),
      ),
    );
  }
}

/// The reference's glyph: Lucide `ArrowUpCircle` — a circle with an arrow
/// pointing up inside it.
///
/// Composed from primitives rather than substituted. The bundled icon font has
/// `arrowUpRight` and `arrowTrendUp`, but neither is this shape, and using one
/// of those put a diagonal arrow inside the badge, which simply read as a
/// different icon. `Icons.keyboard_arrow_up` ships with Flutter, so this needs
/// no new dependency and no font asset.
class _ArrowUpCircle extends StatelessWidget {
  const _ArrowUpCircle({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colour, width: 1.9),
              ),
              child: const SizedBox(width: 20, height: 20),
            ),
            Align(
              // Nudged up so the arrow sits optically centred inside the ring
              // rather than sitting on the circle's centre line.
              alignment: const Alignment(0, 0.18),
              child: Icon(Icons.keyboard_arrow_up, size: 14, color: colour),
            ),
          ],
        ),
      );
}

class UpdateBannerSlot extends StatefulWidget {
  const UpdateBannerSlot({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<UpdateBannerSlot> createState() => UpdateBannerSlotState();
}

class UpdateBannerSlotState extends State<UpdateBannerSlot> {
  /// "Later" hides the banner for this session only. Not persisted: an update
  /// the trader waved off should reappear next launch rather than vanish
  /// forever on a device that never opens Settings.
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    // One check per launch, so the banner can surface an update without the
    // trader having to find Settings and tap CHECK first. The result flows
    // through the service the slot already watches, so no setState is needed:
    // check() emits a new state and the ListenableBuilder rebuilds.
    //
    // Fails into DownloadState.failed, which isRelevant() does not flag, so a
    // transient network error at launch shows nothing rather than an error
    // banner the trader cannot act on. Only an actually-newer build appears.
    //
    // The manifest URL is only present in live builds (BackendService or the
    // build define); in mock mode the provider is absent and this slot returns
    // before reaching here, so this is not a mock-mode network call.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fire-and-forget: check() never throws, it reports via state.
      context.read<UpdateService?>()?.check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<UpdateService?>();
    if (service == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => UpdateBanner(
        service: service,
        dismissed: _dismissed,
        onDismiss: () => setState(() => _dismissed = true),
        onOpenSettings: () {
          // Acting on the banner retires it. Leaving it up while the user is
          // already looking at the App updates panel meant the banner covered
          // the very control they were sent to, so it now clears on the way
          // there rather than sitting over the destination.
          setState(() => _dismissed = true);
          widget.onOpenSettings();
        },
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: Material(
          color: filled ? harborCobalt : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: filled ? Colors.transparent : harborLine,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : harborDim,
                ),
              ),
            ),
          ),
        ),
      );
}