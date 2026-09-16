import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/repositories/cp_repository.dart';
import 'package:samafox/widgets/cp_relationship.dart';

/// Renders the couple card to PNG so the artwork placement can be eyeballed
/// without a device. Run: flutter test test/cp_card_preview_test.dart
void main() {
  testWidgets('cp card preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1100));
    final partner = CpPartner(
      pairId: 1,
      userId: 2,
      name: 'سما',
      displayId: 789012,
      gender: 'female',
      since: DateTime.now().subtract(const Duration(days: 12)),
    );
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF120A2A),
          body: RepaintBoundary(
            key: key,
            child: Column(children: [
              CpRelationshipCard(
                  myAvatarUrl: null,
                  myName: 'فهد الحدبي',
                  myDisplayId: 123456,
                  myGender: 'male',
                  partner: partner),
              CpRelationshipCard(
                  myAvatarUrl: null,
                  myName: 'فهد الحدبي',
                  myDisplayId: 123456,
                  myGender: 'male',
                  partner: partner,
                  compact: true,
                  showTitle: false),
            ]),
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      for (final ctx in tester.allElements) {
        final w = ctx.widget;
        if (w is Image) await precacheImage(w.image, ctx);
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
    final bytes = await tester
        .runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
    final out = Platform.environment['CP_PREVIEW_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
