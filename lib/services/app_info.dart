import 'package:package_info_plus/package_info_plus.dart';

/// The app's version and build (PRD-2.3 §20.2 Settings footer).
class AppVersion {
  const AppVersion(this.version, this.build);

  /// e.g. `2.3.0`.
  final String version;

  /// e.g. `10`.
  final String build;

  /// The footer line: `Flappy Spikes v2.3.0 (10)`.
  String get footer =>
      'Flappy Spikes v$version${build.isEmpty ? '' : ' ($build)'}';
}

/// Reads the installed app's version. The game's default is [NoAppInfo]
/// (tests never touch a plugin); `main.dart` installs [PluginAppInfo].
abstract class AppInfo {
  const AppInfo();

  /// The version, or null when it cannot be read. Never throws.
  Future<AppVersion?> load();
}

/// No version (tests, desktop without the plugin): the footer shows just
/// the game's name.
class NoAppInfo extends AppInfo {
  const NoAppInfo();

  @override
  Future<AppVersion?> load() async => null;
}

/// A fixed version (tests: "faked in tests", §20.5).
class FixedAppInfo extends AppInfo {
  const FixedAppInfo(this.version);

  final AppVersion version;

  @override
  Future<AppVersion?> load() async => version;
}

/// `package_info_plus` (PRD-2.3 §20.4): read once and cached after a success.
/// A failed read is not cached: the next call tries again (a null kept for
/// the whole session would hide the footer's version until the next launch).
/// Every call is try/caught — a failing plugin never takes the game down.
class PluginAppInfo extends AppInfo {
  PluginAppInfo({Future<PackageInfo> Function()? reader})
    : _reader = reader ?? PackageInfo.fromPlatform;

  final Future<PackageInfo> Function() _reader;

  AppVersion? _version;
  Future<AppVersion?>? _pending;

  @override
  Future<AppVersion?> load() {
    final known = _version;
    if (known != null) return Future.value(known);
    return _pending ??= _read().then((version) {
      _version = version;
      _pending = null;
      return version;
    });
  }

  Future<AppVersion?> _read() async {
    try {
      final info = await _reader();
      return AppVersion(info.version, info.buildNumber);
    } catch (_) {
      return null;
    }
  }
}
