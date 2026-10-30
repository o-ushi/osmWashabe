import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:osm_washabe/l10n/app_strings.dart';
import 'package:osm_washabe/notifiers/app_settings.dart';
import 'package:osm_washabe/services/app_preferences.dart';
import 'package:osm_washabe/views/help/help_view.dart';

void main() {
  late AppSettingsNotifier settings;

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'osmWashabe',
      packageName: 'com.osamushikubo.osmWashabe',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettingsNotifier()..bind(await AppPreferences.load());
  });

  test('操作マニュアルURLは言語ごとに固定のpreview先を返す', () {
    expect(
      HelpView.userManualUrlFor('ja'),
      'https://docs.google.com/presentation/d/'
      '${HelpView.userManualPresentationIdJa}/preview',
    );
    expect(
      HelpView.userManualUrlFor('en'),
      'https://docs.google.com/presentation/d/'
      '${HelpView.userManualPresentationIdEn}/preview',
    );
    expect(
      HelpView.userManualUrlFor('vi'),
      'https://docs.google.com/presentation/d/'
      '${HelpView.userManualPresentationIdVi}/preview',
    );
    expect(
      HelpView.userManualUrlFor('fr'),
      HelpView.userManualUrlFor('vi'),
    );
  });

  testWidgets('操作マニュアルをタップすると表示言語のGoogleスライドが開く', (tester) async {
    final originalUrlLauncher = UrlLauncherPlatform.instance;
    final fakeUrlLauncher = _FakeUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakeUrlLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalUrlLauncher);

    settings.language = 'en';

    await tester.pumpWidget(
      MaterialApp(home: HelpView(settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('操作マニュアル'.tr(settings.language)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('help_user_manual')));
    await tester.pumpAndSettle();

    expect(fakeUrlLauncher.launchedUrls, [HelpView.userManualUrlFor('en')]);
    expect(HelpView.userManualUrlFor('en'), endsWith('/preview'));
  });
}

class _FakeUrlLauncherPlatform extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}
