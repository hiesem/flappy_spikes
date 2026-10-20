import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2.5 §3.3 WP-GUARD: one test per reason with a fake channel, the
/// fail-open paths and the non-release rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flappy_spikes/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  IntegrityGuard guard(String os, {bool enforce = true}) =>
      IntegrityGuard(enforce: enforce, platformOverride: os);

  test('Android: the Play app-signing cert is trusted', () async {
    answer(
      (_) => {
        'certs': ['00ff', IntegrityGuard.playCertSha256],
        'installer': 'com.android.vending',
      },
    );
    final g = guard('android');
    await g.start();
    expect(g.trusted, isTrue);
    expect(g.reason, isNull);
  });

  test('Android: another cert is untrusted (sig)', () async {
    answer(
      (_) => {
        'certs': ['5339fe70aa'],
        'installer': 'com.android.vending',
      },
    );
    final events = <String>[];
    final g = guard('android')..onUntrusted = events.add;
    await g.start();
    expect(g.trusted, isFalse);
    expect(g.reason, 'sig');
    expect(events, ['sig']);
  });

  test('Android: a non-Play installer alone stays trusted', () async {
    answer(
      (_) => {
        'certs': [IntegrityGuard.playCertSha256.toUpperCase()],
        'installer': 'com.sec.android.easyMover',
      },
    );
    final events = <String>[];
    final g = guard('android')..onUntrusted = events.add;
    await g.start();
    expect(g.trusted, isTrue);
    expect(events, isEmpty);
  });

  test('Android: no certificate read at all is not a verdict', () async {
    answer((_) => {'certs': <String>[], 'installer': null});
    final g = guard('android');
    await g.start();
    expect(g.trusted, isTrue);
  });

  test('iOS: another team\'s profile is untrusted (ios_team)', () async {
    answer((_) => {'provisionTeam': 'ABCDE12345', 'sandboxReceipt': false});
    final g = guard('ios');
    await g.start();
    expect(g.reason, 'ios_team');
    expect(g.trusted, isFalse);
  });

  test(
    'iOS: no profile (App Store / TestFlight) or our team is trusted',
    () async {
      answer((_) => {'sandboxReceipt': true});
      final a = guard('ios');
      await a.start();
      expect(a.trusted, isTrue);
      answer(
        (_) => {
          'provisionTeam': IntegrityGuard.appleTeamId,
          'sandboxReceipt': false,
        },
      );
      final b = guard('ios');
      await b.start();
      expect(b.trusted, isTrue);
    },
  );

  test('save: markUntrusted from the seal (one event per process)', () {
    final events = <String>[];
    final g = guard('android')..onUntrusted = events.add;
    g.markUntrusted('save');
    g.markUntrusted('iap_fake');
    expect(g.trusted, isFalse);
    expect(g.reason, 'save');
    expect(events, ['save']);
  });

  test('iap_fake: a stored iapFake marker is sticky at start', () async {
    SharedPreferences.setMockInitialValues({IntegrityGuard.iapFakeKey: true});
    answer(
      (_) => {
        'certs': [IntegrityGuard.playCertSha256],
      },
    );
    final g = guard('android');
    await g.start();
    expect(g.reason, 'iap_fake');
    expect(g.trusted, isFalse);
  });

  test('channel error / missing plugin → trusted (fail-open)', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    final a = guard('android');
    await a.start();
    expect(a.trusted, isTrue);
    messenger.setMockMethodCallHandler(channel, null); // MissingPlugin
    final b = guard('ios');
    await b.start();
    expect(b.trusted, isTrue);
  });

  test(
    'non-release builds never enforce (and never ask the platform)',
    () async {
      var asked = 0;
      answer((_) {
        asked++;
        return {
          'certs': ['bad'],
        };
      });
      // The default instance under `flutter test` is a debug build.
      expect(IntegrityGuard().enforce, isFalse);
      final g = guard('android', enforce: false);
      await g.start();
      g.markUntrusted('save');
      expect(asked, 0);
      expect(g.trusted, isTrue);
    },
  );

  test('waitReady is bounded by 2 s and never throws', () async {
    final g = guard('android');
    g.track(Future<void>.delayed(const Duration(days: 1)));
    final sw = Stopwatch()..start();
    await g.waitReady();
    expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
    g.track(Future<void>.error(StateError('x')));
    expect(g.trusted, isTrue);
  });
}
