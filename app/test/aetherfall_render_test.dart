// Renders the أثيرفول preview harness headlessly and writes PNGs, so the
// artwork can be reviewed without an emulator, a backend or a login:
//
//   flutter test test/aetherfall_render_test.dart
//
// Output lands in build/aetherfall-preview/. This is a rendering aid, not an
// assertion — it fails only if a frame cannot be produced at all.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/dev/aetherfall_preview.dart';

const _size = Size(400, 940);

Future<void> _shoot(WidgetTester tester, Widget app, String name) async {
  final key = GlobalKey();

  await tester.binding.setSurfaceSize(_size);
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    DefaultTextStyle(
      style: const TextStyle(fontFamily: 'ElMessiri'),
      child: RepaintBoundary(key: key, child: app),
    ),
  );

  // Asset decoding is real async work, so give the image cache room to resolve
  // before the frame is captured — otherwise every Image.asset paints empty.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
    await tester.pump(const Duration(milliseconds: 120));
  }

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );

  final dir = Directory('build/aetherfall-preview')..createSync(recursive: true);
  final file = File('${dir.path}/$name.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path} (${(file.lengthSync() / 1024).round()} KB)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter test ships a placeholder font that draws every glyph as a box,
    // which makes a screenshot useless for review. Load the app's real face and
    // register it as the default so the captures read like the app does.
    for (final entry in const {
      'ElMessiri': 'assets/fonts/ElMessiri-Regular.ttf',
      'ElMessiriBold': 'assets/fonts/ElMessiri-Bold.ttf',
    }.entries) {
      final data = await rootBundle.load(entry.value);
      await (FontLoader(entry.key)..addFont(Future.value(data))).load();
    }
  });

  testWidgets('base play', (tester) async {
    await _shoot(tester, const AetherfallPreviewApp(), 'base-play');
  });

  testWidgets('skyfire vault', (tester) async {
    await _shoot(tester, const AetherfallPreviewApp(bonus: true), 'skyfire-vault');
  });

  testWidgets('celebration', (tester) async {
    await _shoot(tester, const AetherfallPreviewApp(celebrate: true), 'celebration');
  });
}
