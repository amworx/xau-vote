import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/theme.dart';
import 'package:xauvote/widgets/analysis_verdict_card.dart';

void main() {
  group('analysis card empty states', () {
    Future<void> pumpCard(WidgetTester tester, AnalysisVerdictCard card) async {
      await tester.pumpWidget(
        MaterialApp(theme: harborTheme(), home: Scaffold(body: card)),
      );
      await tester.pump();
    }

    testWidgets('offline waits calmly, never prints the exception', (tester) async {
      await pumpCard(
        tester,
        const AnalysisVerdictCard(
          scan: null,
          error: 'SocketException: Failed host lookup',
          offline: true,
        ),
      );

      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('Analysis failed'), findsNothing);
    });

    testWidgets('a real failure still names itself when online', (tester) async {
      await pumpCard(
        tester,
        const AnalysisVerdictCard(
          scan: null,
          error: 'boom',
          offline: false,
        ),
      );

      expect(find.text('Analysis failed'), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Waiting for connection'), findsNothing);
    });

    testWidgets('never run reads as waiting for history', (tester) async {
      await pumpCard(tester, const AnalysisVerdictCard(scan: null));

      expect(find.text('No analysis yet'), findsOneWidget);
      expect(find.text('Analysis failed'), findsNothing);
    });
  });
}
