import 'package:body_lab/services/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const json =
      '{"version": "1.0.0", "build": 42, "commit": "abc1234", '
      '"apkUrl": "https://example.com/body_lab.apk"}';

  AppUpdater updater(int installedBuild, {String remote = json}) => AppUpdater(
    fetchRemote: () async => remote,
    installed: () async => InstalledVersion('1.0.0', installedBuild),
  );

  test('遠端 build 比較新：回傳新版資訊', () async {
    final release = await updater(41).checkForUpdate();
    expect(release, isNotNull);
    expect(release!.build, 42);
    expect(release.label, '1.0.0（42）');
    expect(release.apkUrl, Uri.parse('https://example.com/body_lab.apk'));
    expect(release.commit, 'abc1234');
  });

  test('同版或較舊：回傳 null', () async {
    expect(await updater(42).checkForUpdate(), isNull);
    expect(await updater(50).checkForUpdate(), isNull);
  });

  test('格式錯誤丟 FormatException', () async {
    expect(
      updater(1, remote: '{"version": "1.0.0"}').checkForUpdate(),
      throwsFormatException,
    );
  });

  test('抓取失敗會把例外丟出去', () async {
    final u = AppUpdater(
      fetchRemote: () async => throw Exception('offline'),
      installed: () async => const InstalledVersion('1.0.0', 1),
    );
    expect(u.checkForUpdate(), throwsException);
  });
}
