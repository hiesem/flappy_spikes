import 'package:flappy_spikes/services/redact.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §4 diagnostics / QA S7-18: no credential reaches a diagnostic
/// print or an analytics parameter.
void main() {
  const jwt =
      'eyJhbGciOiJSUzI1NiIsImtpZCI6IjEifQ.eyJzdWIiOiIxMjM0NSJ9.c2lnbmF0dXJl';
  const access = 'ya29.a0AfB_byC9xyzSECRET123';

  group('PRD-2.2 §4 S7-18 redactSecrets', () {
    test('the failed Play Games link message (device evidence)', () {
      final out = redactSecrets(
        '[firebase_auth/unknown] '
        'http://localhost?access_token=$access&providerId=playgames.google.com',
      );
      expect(out, isNot(contains('ya29')));
      expect(out, isNot(contains('SECRET')));
      expect(out, contains('[firebase_auth/unknown]'));
      expect(out, contains('http://localhost?<redacted>'));
    });

    test('key=value / JSON / bearer / JWT / auth codes outside URLs', () {
      final cases = {
        'access_token=abc123DEF': 'abc123DEF',
        'id_token: $jwt': 'eyJ',
        '{"idToken":"opaque-value-9"}': 'opaque-value-9',
        'refreshToken=r-1-2-3, code ok': 'r-1-2-3',
        'Authorization: Bearer abc.def.ghi': 'abc.def',
        'serverAuthCode 4/0AbCdEfGhIjKlMnOp': '4/0AbCd',
        'raw $jwt end': 'eyJ',
        'token $access': 'ya29',
        'api_key=AIzaFAKE': 'AIzaFAKE',
        'https://x.example/cb#access_token=zzz&state=1': 'zzz',
      };
      cases.forEach((input, secret) {
        final out = redactSecrets(input);
        expect(out, isNot(contains(secret)), reason: input);
        expect(out, contains('<redacted>'), reason: input);
      });
    });

    test('ordinary diagnostics are unchanged', () {
      for (final s in [
        'versus: search (reads 3 pool 12)',
        'GameServices pgs_error: op=submit code=timeout message=',
        'TimeoutException after 0:00:08.000000: Future not completed',
        '[cloud_firestore/permission-denied] The caller does not have permission',
        'App Check activated (debug provider)',
      ]) {
        expect(redactSecrets(s), s);
      }
    });

    test('analytics: track() strips credentials from every String value', () {
      final spy = AnalyticsSpy();
      spy.track('iap_error', {
        'reason': 'failed http://localhost?access_token=$access',
        'code': 'x id_token=$jwt',
        'count': 3,
      });
      final (name, params) = analyticsLog(spy).single;
      expect(name, 'iap_error');
      expect('$params', isNot(contains('ya29')));
      expect('$params', isNot(contains('eyJ')));
      expect(params!['count'], 3);
    });

    test('redactParams keeps keys and non-String values', () {
      expect(redactParams(null), isNull);
      expect(redactParams({'n': 1, 's': 'ok'}), {'n': 1, 's': 'ok'});
    });
  });
}
