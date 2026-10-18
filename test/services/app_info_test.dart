import 'package:flappy_spikes/services/app_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _info() => PackageInfo(
  appName: 'Flappy Spikes',
  packageName: 'com.flappyspikes.flappyspikes',
  version: '2.4.0',
  buildNumber: '36',
);

void main() {
  // WP-SET: a failed read used to stay cached for the whole session, so the
  // Settings footer never got its version back until the next launch.
  test('PluginAppInfo keeps a failed read out of the cache', () async {
    var reads = 0;
    final info = PluginAppInfo(
      reader: () async {
        reads++;
        if (reads == 1) throw StateError('plugin not ready');
        return _info();
      },
    );
    expect(
      await info.load(),
      isNull,
      reason: 'the failed read gives no version',
    );
    expect((await info.load())?.footer, 'Flappy Spikes v2.4.0 (36)');
    expect(reads, 2, reason: 'the next call reads again');
  });

  test('PluginAppInfo reads once after a success and shares a read in '
      'flight', () async {
    var reads = 0;
    final info = PluginAppInfo(
      reader: () async {
        reads++;
        return _info();
      },
    );
    final first = info.load();
    final second = info.load();
    expect((await first)?.footer, 'Flappy Spikes v2.4.0 (36)');
    expect((await second)?.footer, 'Flappy Spikes v2.4.0 (36)');
    expect((await info.load())?.footer, 'Flappy Spikes v2.4.0 (36)');
    expect(reads, 1);
  });

  test('PluginAppInfo never throws, even when the reader throws at once', () {
    final info = PluginAppInfo(reader: () => throw StateError('no plugin'));
    expect(info.load(), completion(isNull));
  });
}
