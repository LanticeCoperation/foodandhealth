import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// CI 每次發佈時寫到 Release「latest」的版本資訊。
const kVersionUrl =
    'https://github.com/LanticeCoperation/foodandhealth/releases/download/latest/version.json';

/// Release「latest」的頁面（給沒有直接下載網址時用）。
const kReleasePageUrl =
    'https://github.com/LanticeCoperation/foodandhealth/releases/tag/latest';

/// version.json 的內容。
///
/// ```json
/// { "version": "1.0.0", "build": 42, "commit": "134d729",
///   "apkUrl": "https://github.com/.../releases/download/latest/body_lab.apk" }
/// ```
class AppRelease {
  const AppRelease({
    required this.version,
    required this.build,
    required this.apkUrl,
    this.commit,
  });

  final String version;

  /// 對應 Android versionCode / iOS CFBundleVersion；CI 用 run number，只增不減。
  final int build;
  final Uri apkUrl;
  final String? commit;

  String get label => '$version（$build）';

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final build = json['build'];
    final apkUrl = json['apkUrl'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('缺少 version');
    }
    if (build is! int) throw const FormatException('缺少 build');
    if (apkUrl is! String) throw const FormatException('缺少 apkUrl');
    return AppRelease(
      version: version,
      build: build,
      apkUrl: Uri.parse(apkUrl),
      commit: json['commit'] as String?,
    );
  }
}

/// 目前安裝的版本。
class InstalledVersion {
  const InstalledVersion(this.version, this.build);

  final String version;
  final int build;

  String get label => '$version（$build）';
}

/// 比對 GitHub Release 上的 version.json 和目前安裝的 build number。
class AppUpdater {
  AppUpdater({
    Future<String> Function()? fetchRemote,
    Future<InstalledVersion> Function()? installed,
  }) : _fetchRemote = fetchRemote ?? _fetchUrl,
       _installed = installed ?? _platformVersion;

  final Future<String> Function() _fetchRemote;
  final Future<InstalledVersion> Function() _installed;

  static Future<String> _fetchUrl() async {
    final response = await http
        .get(Uri.parse(kVersionUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'HTTP ${response.statusCode}',
        response.request?.url,
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  static Future<InstalledVersion> _platformVersion() async {
    final info = await PackageInfo.fromPlatform();
    return InstalledVersion(info.version, int.tryParse(info.buildNumber) ?? 0);
  }

  Future<InstalledVersion> installed() => _installed();

  /// 有比目前新的版本就回傳；已是最新回傳 null。網路或格式錯誤會丟例外。
  Future<AppRelease?> checkForUpdate() async {
    final release = AppRelease.fromJson(
      jsonDecode(await _fetchRemote()) as Map<String, dynamic>,
    );
    final current = await _installed();
    return release.build > current.build ? release : null;
  }
}
