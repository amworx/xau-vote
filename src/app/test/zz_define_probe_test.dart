import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/config.dart';

void main() {
  test('define probe', () {
    // ignore: avoid_print
    print('PROBE-URL [$updateManifestUrl] configured=$updatesConfigured');
    expect(true, isTrue);
  });
}
