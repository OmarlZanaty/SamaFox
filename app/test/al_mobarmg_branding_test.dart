// AL MOBARMG developer signature: it appears once on each of the three
// approved screens, never overflows (small phone, tablet, desktop, Arabic RTL,
// large text), is one tap target that opens the site in the EXTERNAL browser,
// and is announced to screen readers. Screenshots for review land in
// build/branding-preview/.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:samafox/providers/auth_provider.dart';
import 'package:samafox/providers/localization_provider.dart';
import 'package:samafox/repositories/auth_repository.dart';
import 'package:samafox/screens/about_screen.dart';
import 'package:samafox/screens/login_screen.dart';
import 'package:samafox/screens/splash_screen.dart';
import 'package:samafox/theme/app_theme.dart';
import 'package:samafox/widgets/branding/al_mobarmg_branding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records launches instead of opening a browser.
class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<(String, PreferredLaunchMode)> launched = [];
  bool fail = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (fail) throw PlatformException(code: 'NO_BROWSER');
    launched.add((url, options.mode));
    return true;
  }
}

/// No session check, no network: the splash and login screens only need an
/// auth state to read.
class _NoRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

class _IdleAuth extends AuthNotifier {
  _IdleAuth() : super(_NoRepo());
  @override
  Future<void> checkAuthStatus() => Completer<void>().future;
}

const _sizes = {
  'small-phone': Size(320, 568),
  'phone': Size(393, 852),
  'tablet': Size(834, 1194),
  'desktop': Size(1440, 900),
};

late SharedPreferences _prefs;

Widget _app(Widget home,
    {required Locale locale,
    ThemeMode mode = ThemeMode.dark,
    double textScale = 1}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      authStateProvider.overrideWith((ref) => _IdleAuth()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        textTheme: AppTheme.lightTheme.textTheme
            .apply(fontFamily: 'Roboto', fontFamilyFallback: ['ElMessiri']),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        textTheme: AppTheme.darkTheme.textTheme
            .apply(fontFamily: 'Roboto', fontFamilyFallback: ['ElMessiri']),
      ),
      themeMode: mode,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Same as main.dart: Arabic lays out right to left.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
              fontFamily: 'Roboto', fontFamilyFallback: ['ElMessiri']),
          child: child!,
        ),
      ),
      home: home,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // Asset and SVG decoding is real async work.
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.5));
  final bytes = await tester
      .runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  final dir = Directory('build/branding-preview')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeLauncher launcher;

  setUpAll(() async {
    // flutter test draws every glyph as a box; load real faces so the
    // screenshots read like the app. Roboto for Latin, ElMessiri for Arabic.
    // flutter_tester lives under <flutter>/bin/cache/artifacts/engine/...;
    // the Material fonts sit beside it in artifacts/material_fonts.
    var dir = File(Platform.resolvedExecutable).parent;
    while (dir.path != dir.parent.path && !dir.path.endsWith('artifacts')) {
      dir = dir.parent;
    }
    final sdkFonts = '${dir.path}/material_fonts';
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final p in paths) {
        final f = File(p);
        if (f.existsSync())
          loader
              .addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      }
      await loader.load();
    }

    await load('Roboto', [
      '$sdkFonts/roboto-regular.ttf',
      '$sdkFonts/roboto-bold.ttf',
      '$sdkFonts/roboto-medium.ttf'
    ]);
    await load('MaterialIcons', ['$sdkFonts/materialicons-regular.otf']);
    await load('ElMessiri', ['assets/fonts/ElMessiri-Regular.ttf']);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    // Build number 0 makes the update gate stand aside without a network call.
    PackageInfo.setMockInitialValues(
      appName: 'SamaFox',
      packageName: 'com.almobarmg.samafox',
      version: '1.0.47',
      buildNumber: '0',
      buildSignature: '',
      installerStore: null,
    );
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  final screens = <String, Widget Function()>{
    'splash': () => const SplashScreen(),
    'login': () => const LoginScreen(),
    'about': () => const AboutScreen(),
  };

  for (final screen in screens.entries) {
    for (final size in _sizes.entries) {
      for (final lang in const ['ar', 'en']) {
        testWidgets(
            '${screen.key} · ${size.key} · $lang: one signature, no overflow',
            (tester) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(RepaintBoundary(
            child: _app(screen.value(), locale: Locale(lang)),
          ));
          await _settle(tester);

          expect(tester.takeException(), isNull);
          expect(find.byType(AlMobarmgBranding), findsOneWidget);
          // Secondary to the app: smaller than any of SamaFox's own marks.
          final brand = tester.getSize(find.byType(AlMobarmgBranding));
          expect(brand.width, lessThanOrEqualTo(480));
          if (screen.key != 'splash' || size.key == 'phone') {
            await _shoot(tester, '${screen.key}-${size.key}-$lang');
          }
        });
      }
    }
  }

  testWidgets('small phone with 1.5x text still fits (login and about scroll)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final screen in screens.values) {
      await tester.pumpWidget(RepaintBoundary(
        child: _app(screen(), locale: const Locale('ar'), textScale: 1.5),
      ));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AlMobarmgBranding), findsOneWidget);
    }
    await _shoot(tester, 'about-small-phone-ar-textscale150');
  });

  testWidgets('About in light mode', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      child: _app(const AboutScreen(),
          locale: const Locale('en'), mode: ThemeMode.light),
    ));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await _shoot(tester, 'about-phone-en-light');
  });

  group('the whole block is one link to the site', () {
    Future<void> pumpCompact(WidgetTester tester) async {
      await tester.pumpWidget(_app(
        const Scaffold(
            body: Center(
                child: AlMobarmgBranding(caption: AlMobarmgCaption.poweredBy))),
        locale: const Locale('en'),
      ));
      await _settle(tester);
    }

    testWidgets('tapping the caption, not the logo, opens it externally',
        (tester) async {
      await pumpCompact(tester);
      await tester.tap(find.text('Powered by'));
      await tester.pump();
      expect(launcher.launched, [
        ('https://www.almobarmg.com', PreferredLaunchMode.externalApplication)
      ]);
    });

    testWidgets('tapping the website line of the full card opens it too',
        (tester) async {
      await tester.pumpWidget(_app(
        const Scaffold(
            body: Center(
                child: AlMobarmgBranding(variant: AlMobarmgVariant.full))),
        locale: const Locale('ar'),
      ));
      await _settle(tester);
      await tester.tap(find.text('Software Company'));
      await tester.pump();
      expect(launcher.launched.single.$1, 'https://www.almobarmg.com');
    });

    testWidgets('keyboard: Tab then Enter activates it', (tester) async {
      await pumpCompact(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(launcher.launched, hasLength(1));
    });

    testWidgets('a phone that cannot open it does not crash', (tester) async {
      launcher.fail = true;
      await pumpCompact(tester);
      await tester.tap(find.byType(AlMobarmgBranding));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen readers hear one link with a clear label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCompact(tester);
      expect(find.bySemanticsLabel('Visit AL MOBARMG Software Company website'),
          findsOneWidget);
      // The parts are not read out one by one.
      expect(find.bySemanticsLabel('Powered by'), findsNothing);
      handle.dispose();
    });

    testWidgets('Arabic caption, Latin name kept left-to-right',
        (tester) async {
      await tester.pumpWidget(_app(
        const Scaffold(body: Center(child: AlMobarmgBranding())),
        locale: const Locale('ar'),
      ));
      await _settle(tester);
      expect(find.text('تطوير'), findsOneWidget);
      final name = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.textSpan?.toPlainText() ?? '') == 'AL MOBARMG',
      ));
      expect(name.textDirection, TextDirection.ltr);
    });
  });
}
