import 'package:flutter/material.dart';
import 'package:xau_core/analysis/independence.dart';

import '../theme.dart';

/// Renders the three independence figures with the settled wording.
///
/// The rules this enforces, in order of importance:
///
///  * **"0 of 0 sources" never renders.** A denominator of zero is not a
///    division, it is the absence of external sources. It reads as an error, so
///    the line is replaced entirely rather than printed.
///  * **The word "sources" never appears near a method count.** "4 methods
///    agree" is a statement about how many readers point the same way. Calling
///    it "independent methods" would claim exactly what is not true.
///  * **Method agreement is never dressed as consensus.** It sits beneath the
///    source line, in its own terms, with the dataset count that makes the
///    diversity concrete.
class IndependenceLine extends StatelessWidget {
  const IndependenceLine({
    super.key,
    required this.result,
    this.fallbackAgree,
    this.fallbackTotal,
  });

  final IndependenceResult? result;

  /// Fixture counts for the offline build.
  ///
  /// Offline there is no provenance to score, so this widget renders nothing and
  /// the mock would silently lose the agreement figure it has always shown.
  /// These keep mock mode informative while leaving live wording untouched.
  final int? fallbackAgree;
  final int? fallbackTotal;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      final a = fallbackAgree;
      final t = fallbackTotal;
      if (a == null || t == null) return const SizedBox.shrink();
      return Text(
        '$a of $t sources agree',
        style: const TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 10,
          color: harborInk,
        ),
      );
    }

    // No external publisher yet: this is a real state, not a failure.
    if (!r.canShowSourceRatio) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No external sources yet',
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              color: harborInk,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (r.analyticalMethods > 0) ...[
            const SizedBox(height: 3),
            Text(
              '${r.analyticalMethods} method${r.analyticalMethods == 1 ? '' : 's'} agree'
              '${r.upstreamDatasets > 0 ? ' · ${r.upstreamDatasets} upstream dataset'
                  '${r.upstreamDatasets == 1 ? '' : 's'}' : ''}',
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 9,
                color: harborDim,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${r.externalVoices} of ${r.eligiblePublishers} sources agree',
          style: const TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            color: harborInk,
          ),
        ),
        if (r.analyticalMethods > 0) ...[
          const SizedBox(height: 3),
          Text(
            '${r.analyticalMethods} method${r.analyticalMethods == 1 ? '' : 's'} agree',
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9,
              color: harborDim,
            ),
          ),
        ],
      ],
    );
  }
}