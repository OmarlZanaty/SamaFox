// Renders the أستيريون preview harness headlessly and writes PNGs, so the
// artwork can be reviewed without an emulator, a backend or a login:
//
//   flutter test test/asterion_render_test.dart
//
// Output lands in build/asterion-preview/. The captures are a rendering aid,
// but the narrow-screen cases are a real assertion: a RenderFlex overflow
// throws during layout and fails the test.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/dev/asterion_preview.dart';

const _size = Size(400, 940);

/// The narrowest screen the game claims to support.
const _narrow = Size(360, 780);

Future<void> _shoot(WidgetTester tester, Widget app, String name, {Size size = _size}) async {
  final key = GlobalKey();

  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    DefaultTextStyle(
      style: const TextStyle(fontFamily: 'ElMessiri'),
      child: RepaintBoundary(key: key, child: app),
    ),
  );

  // Give any implicit animation and the image cache room to settle before the
  // frame is captured.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 160));
  }

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );

  final dir = Directory('build/asterion-preview')..createSync(recursive: true);
  final file = File('${dir.path}/$name.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path} (${(file.lengthSync() / 1024).round()} KB)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter test ships a placeholder font that draws every glyph as a box,
    // which makes a screenshot useless for review. Load the app's real face so
    // the captures read like the app does.
    for (final entry in const {
      'ElMessiri': 'assets/fonts/ElMessiri-Regular.ttf',
      'ElMessiriBold': 'assets/fonts/ElMessiri-Bold.ttf',
    }.entries) {
      final data = await rootBundle.load(entry.value);
      await (FontLoader(entry.key)..addFont(Future.value(data))).load();
    }
  });

  testWidgets('board mid-cascade', (tester) async {
    await _shoot(tester, const AsterionPreviewApp(), 'board');
  });

  testWidgets('symbol sheet', (tester) async {
    await _shoot(tester, const AsterionPreviewApp(scene: PreviewScene.symbols), 'symbols');
  });

  testWidgets('trial entry', (tester) async {
    await _shoot(tester, const AsterionPreviewApp(scene: PreviewScene.trial), 'trial');
  });

  testWidgets('celebration', (tester) async {
    await _shoot(
      tester,
      const AsterionPreviewApp(scene: PreviewScene.celebration),
      'celebration',
    );
  });

  testWidgets('high contrast', (tester) async {
    await _shoot(tester, const AsterionPreviewApp(highContrast: true), 'high-contrast');
  });

  // A 360px sweep. Any overflow throws during layout and fails the test, so
  // this is an assertion, not just a screenshot.
  testWidgets('360px board', (tester) async {
    await _shoot(tester, const AsterionPreviewApp(), 'narrow-board', size: _narrow);
  });

  testWidgets('360px celebration', (tester) async {
    await _shoot(
      tester,
      const AsterionPreviewApp(scene: PreviewScene.celebration),
      'narrow-celebration',
      size: _narrow,
    );
  });
}
