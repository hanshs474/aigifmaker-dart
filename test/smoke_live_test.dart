// Free live smoke tests against https://aigifmaker.ai. No generation runs.
//
//   dart test --tags live
@Tags(['live'])
library;

import 'package:aigifmaker/aigifmaker.dart';
import 'package:test/test.dart';

void main() {
  test('invalid key -> AuthError', () async {
    final c = Aigifmaker(apiKey: 'sk-invalidtest000');
    await expectLater(c.credits(), throwsA(isA<AuthError>()));
    c.close();
  });

  test('no key -> AuthError (wall)', () async {
    final c = Aigifmaker(apiKey: '');
    if (c.apiKey.isNotEmpty) {
      markTestSkipped('unset AIGIFMAKER_API_KEY to run this check');
      return;
    }
    await expectLater(
        c.submit('smoke test: a blinking star'), throwsA(isA<AuthError>()));
    c.close();
  });
}
