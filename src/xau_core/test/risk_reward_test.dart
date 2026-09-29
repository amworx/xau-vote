import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

void main() {
  group('RiskReward (spec §11 exact numbers)', () {
    test('LONG: entry 4278 SL 4263 reproduces 15 / 17 / 37 / 62', () {
      final r = RiskReward.calculate(
        entryPrice: 4278,
        stopLoss: 4263,
        takeProfits: [4295, 4315, 4340],
        direction: Direction.long,
      );
      expect(r.risk, 15);
      expect(r.rewards, [17, 37, 62]);
      expect(r.ratios[0], closeTo(1.13, 0.01));
      expect(r.ratios[1], closeTo(2.47, 0.01));
      expect(r.ratios[2], closeTo(4.13, 0.01));
    });

    test('SHORT mirrors the math', () {
      final r = RiskReward.calculate(
        entryPrice: 4278,
        stopLoss: 4293,
        takeProfits: [4261],
        direction: Direction.short,
      );
      expect(r.risk, 15);
      expect(r.rewards, [17]);
      expect(r.ratios[0], closeTo(1.13, 0.01));
    });

    test('fromZoneMid uses the mid price', () {
      final r = RiskReward.fromZoneMid(
        entryZone: PriceRange(low: 4275, high: 4281),
        stopLoss: 4263,
        takeProfits: [4295],
        direction: Direction.long,
      );
      // Mid 4278 → risk 15, reward 17.
      expect(r.risk, 15);
      expect(r.rewards, [17]);
    });

    test('worst edge: LONG pays the high, SHORT the low', () {
      final zone = PriceRange(low: 4275, high: 4280);
      expect(RiskReward.conservativeEdge(zone, Direction.long), 4280);
      expect(RiskReward.conservativeEdge(zone, Direction.short), 4275);
      final worst = RiskReward.fromWorstEdge(
        entryZone: zone,
        stopLoss: 4263,
        takeProfits: [4295],
        direction: Direction.long,
      );
      expect(worst.risk, 17);
      expect(worst.rewards, [15]);
    });

    test('neutral direction throws', () {
      expect(
          () => RiskReward.calculate(
              entryPrice: 1,
              stopLoss: 0,
              takeProfits: [2],
              direction: Direction.neutral),
          throwsArgumentError);
      expect(
          () => RiskReward.conservativeEdge(
              PriceRange(low: 1, high: 2), Direction.neutral),
          throwsArgumentError);
    });

    test('non-positive risk throws', () {
      expect(
          () => RiskReward.calculate(
              entryPrice: 4260,
              stopLoss: 4263,
              takeProfits: [4295],
              direction: Direction.long),
          throwsArgumentError);
    });
  });
}
