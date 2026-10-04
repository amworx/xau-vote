/// Expected market reaction to a scheduled economic release.
///
/// # What this is, and what it is not
///
/// This is a *contextual expectation* attached to an event: what this release
/// has historically tended to do to gold, and what the current regime implies
/// for this occurrence. It is deliberately NOT a signal, NOT a vote, and NOT a
/// probability of profit (product rules 1 and 9; spec §7).
///
/// An event may suppress, delay or annotate a setup. It never creates one, and
/// nothing here can move the 15M consensus.
///
/// # Why "no prediction" is a first-class answer
///
/// A confident-looking direction invented from a missing figure is worse than no
/// answer at all: a trader would size a position against it. So this module
/// returns [EventBias.none] with an explicit basis whenever the inputs cannot
/// support a view:
///
/// * the release has no forecast or no previous value — there is nothing to
///   compare a surprise against;
/// * the release is confounded with another high-impact release in the same
///   window, so the reaction cannot be attributed to either;
/// * the currency has no established direct relationship to gold;
/// * the event is a scheduled repeat with no regime context.
///
/// # Gold's relationships used here
///
/// * **USD data is inverse for gold.** A hotter-than-expected US print tends to
///   lift yields and the dollar, which pressures gold; a cooler print tends to
///   do the opposite. This is a tendency, not a certainty, and it is why the
///   output is an expectation and never a certainty.
/// * **Inflation and labour prints** are the cleanest cases: they move real
///   yields directly.
/// * **Central-bank rate decisions** split: a hawkish hold is hawkish, but the
///   statement and press conference frequently dominate the headline number,
///   so a same-size surprise is treated as a weaker signal than a data print.
library;

/// Direction the release is expected to push gold.
///
/// [none] is a real answer, not a failure to compute.
enum EventBias { bullish, bearish, neutral, none }

/// Why [EventBias] was reached, in the app's reason-code vocabulary.
///
/// A basis is always present, including for [EventBias.none], so the UI can say
/// *why* it declined to answer instead of rendering a blank.
enum EventBasis {
  /// A figure landed above the forecast: hawkish USD pressure on gold.
  upsideSurprise,

  /// A figure landed below the forecast: dovish USD relief for gold.
  downsideSurprise,

  /// A data print in line with expectations: little to move.
  inlineData,

  /// A central-bank decision, where the statement outweighs the number.
  centralBankDecision,

  /// No forecast value recorded, so no surprise can be defined.
  noForecast,

  /// No previous value recorded, so there is no baseline to compare against.
  noPrevious,

  /// Another high-impact release sits in the same window and its reaction
  /// cannot be separated from this one.
  confounded,

  /// The currency has no established direct relationship to gold.
  noGoldLinkage,

  /// The release has not happened yet and no regime context is available.
  awaitingRelease,
}

/// Severity of the expected reaction, used for display weight only.
///
/// Never rendered as a probability or as a chance of profit.
enum EventImpactStrength { minor, notable, strong, unknown }

/// A single release's expected effect on gold.
class EventOutlook {
  const EventOutlook({
    required this.bias,
    required this.basis,
    required this.strength,
    this.minutesToRelease,
    this.confoundedBy = const [],
  });

  /// The expected direction, or [EventBias.none] when no view is supported.
  final EventBias bias;

  /// Why this bias was reached.
  final EventBasis basis;

  final EventImpactStrength strength;

  /// Time until the release, when known. Null for an already-released figure.
  final Duration? minutesToRelease;

  /// Other releases that make this one hard to attribute.
  final List<String> confoundedBy;

  /// True when the module declined to answer and must be shown as such.
  bool get hasNoPrediction => bias == EventBias.none;

  /// One-line reason for the UI. Never contains a probability.
  String get explanation => switch (bias) {
        EventBias.bullish => switch (basis) {
            EventBasis.downsideSurprise =>
              'Cooler than expected · tends to ease yields and lift gold',
            _ => 'Historically a supportive backdrop for gold',
          },
        EventBias.bearish => switch (basis) {
            EventBasis.upsideSurprise =>
              'Hotter than expected · tends to lift yields and weigh on gold',
            _ => 'Historically a headwind for gold',
          },
        EventBias.neutral => 'Little historical reaction for gold',
        EventBias.none => switch (basis) {
            EventBasis.noForecast => 'No forecast recorded · no prediction',
            EventBasis.noPrevious => 'No previous value · no baseline',
            EventBasis.confounded =>
              'Coincides with another high-impact release · no prediction',
            EventBasis.noGoldLinkage =>
              'No direct gold linkage for this currency',
            EventBasis.awaitingRelease =>
              'Awaiting the release · no prediction yet',
            _ => 'No prediction',
          },
      };

  @override
  String toString() =>
      'EventOutlook(${bias.name}, ${basis.name}, ${strength.name})';
}

/// The figure values a release can have.
class ReleaseFigures {
  const ReleaseFigures({this.actual, this.forecast, this.previous});

  final double? actual;
  final double? forecast;
  final double? previous;

  /// True once the release has happened and the actual is known.
  bool get released => actual != null;
}

/// Impact tier of a release, as the calendar stores it.
enum ReleaseImpact { low, medium, high }

/// One release being evaluated.
///
/// Not const-constructible: [others] is populated by the engine when it
/// evaluates a window, so the field is mutable by design.
class ReleaseInput {
  ReleaseInput({
    required this.id,
    required this.title,
    required this.currency,
    required this.impact,
    required this.figures,
    required this.startsAtUtc,
    this.now,
  });

  /// Stable identity, so a window can tell releases apart while checking for
  /// coincident events.
  final String id;

  final String title;
  final String currency;
  final ReleaseImpact impact;
  final ReleaseFigures figures;
  final DateTime startsAtUtc;

  /// Injectable clock. Null means "read the real clock", which is right for the
  /// app and wrong for a test, so tests always pin it.
  final DateTime? now;

  /// Every other release in the window, used for the confounded check.
  List<ReleaseInput> others = const [];

  /// The effective clock for this evaluation.
  DateTime get clock => now ?? DateTime.now().toUtc();

  /// True when this release is a central-bank decision rather than a data print.
  bool get isCentralBank {
    final t = title.toLowerCase();
    return t.contains('fomc') ||
        t.contains('rate decision') ||
        t.contains('interest rate') ||
        t.contains('ecb') ||
        t.contains('boe');
  }

  /// Minutes until release; negative once it has happened.
  int get minutesAway => startsAtUtc.difference(clock).inMinutes;
}

/// Evaluates a release's expected effect on gold.
///
/// Pure and deterministic: given the same inputs it always returns the same
/// outlook, and it never reaches for data it was not given.
class EventOutlookEngine {
  const EventOutlookEngine();

  /// Releases within this many minutes of each other are treated as
  /// confounded. Below the window a reaction can be attributed to one release;
  /// above it the move is a blend nobody can separate.
  static const int confoundWindowMinutes = 60;

  /// Computes the outlook for [release].
  EventOutlook evaluate(ReleaseInput release) {
    final figures = release.figures;

    // 1. Coincidence is a property of the window, not of the figures, so it is
    //    checked first: when two releases collide that is the more actionable
    //    thing to say, and it stays true whatever the data eventually shows.
    final confounded = _confoundedWith(release);
    if (confounded.isNotEmpty) {
      return _none(
        EventBasis.confounded,
        release,
        strength: EventImpactStrength.unknown,
        confoundedBy: confounded,
      );
    }

    // 2. A figure without a forecast cannot be a surprise, and a figure without
    //    a previous has nothing to compare against.
    if (figures.forecast == null) {
      return _none(
        EventBasis.noForecast,
        release,
        strength: _strength(release),
      );
    }
    if (figures.previous == null) {
      return _none(
        EventBasis.noPrevious,
        release,
        strength: _strength(release),
      );
    }

    // 3. Only USD releases have an established direct line to gold here. Other
    //    currencies are reported as neutral rather than guessed at.
    if (release.currency.toUpperCase() != 'USD') {
      return EventOutlook(
        bias: EventBias.neutral,
        basis: EventBasis.noGoldLinkage,
        strength: _strength(release),
        minutesToRelease: _minutes(release),
      );
    }

    // 4. Before the release there is no actual to compare, so this can only
    //    describe what the event is, not what it will do to gold today.
    if (!figures.released) {
      return EventOutlook(
        bias: EventBias.none,
        basis: EventBasis.awaitingRelease,
        strength: _strength(release),
        minutesToRelease: _minutes(release),
      );
    }

    // 5. The surprise itself.
    final surprise = figures.actual! - figures.forecast!;
    // A tolerance keeps float noise on an unchanged figure from reading as a
    // surprise, which would otherwise print a confident direction for nothing.
    final tolerance = (figures.forecast!.abs() * 0.0005).clamp(0.01, double.infinity);
    final basis = release.isCentralBank
        ? EventBasis.centralBankDecision
        : surprise > tolerance
            ? EventBasis.upsideSurprise
            : surprise < -tolerance
                ? EventBasis.downsideSurprise
                : EventBasis.inlineData;

    final bias = switch (basis) {
      EventBasis.upsideSurprise => EventBias.bearish,
      EventBasis.downsideSurprise => EventBias.bullish,
      EventBasis.centralBankDecision => EventBias.neutral,
      _ => EventBias.neutral,
    };

    return EventOutlook(
      bias: bias,
      basis: basis,
      strength: _strength(release),
      minutesToRelease: _minutes(release),
    );
  }

  /// Evaluates a whole window, so confounded releases see each other.
  List<EventOutlook> evaluateAll(List<ReleaseInput> releases) {
    for (final r in releases) {
      r.others = releases.where((o) => o.id != r.id).toList(growable: false);
    }
    return releases.map(evaluate).toList(growable: false);
  }

  /// Titles of high-impact releases close enough in time to confound [release].
  List<String> _confoundedWith(ReleaseInput release) {
    if (release.impact != ReleaseImpact.high) return const [];
    final out = <String>[];
    for (final other in release.others) {
      if (other.impact != ReleaseImpact.high) continue;
      final gap =
          (other.startsAtUtc.difference(release.startsAtUtc)).inMinutes.abs();
      if (gap <= confoundWindowMinutes) out.add(other.title);
    }
    return out;
  }

  EventOutlook _none(
    EventBasis basis,
    ReleaseInput release, {
    required EventImpactStrength strength,
    List<String> confoundedBy = const [],
  }) {
    return EventOutlook(
      bias: EventBias.none,
      basis: basis,
      strength: strength,
      minutesToRelease: _minutes(release),
      confoundedBy: confoundedBy,
    );
  }

  Duration? _minutes(ReleaseInput release) =>
      release.figures.released ? null : Duration(minutes: release.minutesAway);

  EventImpactStrength _strength(ReleaseInput release) => switch (release.impact) {
        ReleaseImpact.high => EventImpactStrength.strong,
        ReleaseImpact.medium => EventImpactStrength.notable,
        ReleaseImpact.low => EventImpactStrength.minor,
      };
}