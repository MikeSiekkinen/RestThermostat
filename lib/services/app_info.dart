import 'package:package_info_plus/package_info_plus.dart';

/// Thin wrapper around [PackageInfo] so the Settings About section can be
/// rendered in widget tests without invoking the plugin (which requires a
/// platform channel that isn't bound in pure-Dart `flutter_test`). Production
/// code uses [PackageInfoAppInfo]; tests inject [StaticAppInfo].
abstract class AppInfo {
  /// Semver from `pubspec.yaml`, e.g. `1.0.0`.
  String get version;

  /// Build identifier from `pubspec.yaml`, e.g. `1` in `1.0.0+1`.
  String get buildNumber;
}

class PackageInfoAppInfo implements AppInfo {
  final PackageInfo _info;
  const PackageInfoAppInfo(this._info);

  static Future<PackageInfoAppInfo> load() async =>
      PackageInfoAppInfo(await PackageInfo.fromPlatform());

  @override
  String get version => _info.version;

  @override
  String get buildNumber => _info.buildNumber;
}

class StaticAppInfo implements AppInfo {
  @override
  final String version;
  @override
  final String buildNumber;

  const StaticAppInfo({required this.version, required this.buildNumber});
}
