import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/widgets/user_name_text.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('gradient name paints text without ShaderMask ($direction)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Directionality(
            textDirection: direction,
            child: const UserNameText(
              'Room member',
              nameGradient: ['#FF0000', '#0000FF'],
              style: TextStyle(color: Colors.green, fontSize: 20),
              maxLines: 2,
              overflow: TextOverflow.fade,
              textAlign: TextAlign.end,
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
      expect(find.text('Room member'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      final text = tester.widget<Text>(find.text('Room member'));
      expect(text.style!.foreground!.shader, isNotNull);
      expect(text.style!.color, isNull);
      expect(text.style!.fontSize, 20);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.fade);
      expect(text.textAlign, TextAlign.end);
    });
  }

  testWidgets('a single gradient colour falls back to nameColor',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: UserNameText(
        'Single colour',
        nameGradient: ['#123456'],
        nameColor: '#ABCDEF',
      ),
    ));

    final text = tester.widget<Text>(find.text('Single colour'));
    expect(text.style!.color, const Color(0xFFABCDEF));
    expect(text.style!.foreground, isNull);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('no valid gradient preserves the name colour fallback',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: UserNameText(
        'Solid name',
        nameGradient: ['invalid'],
        nameColor: '#ABCDEF',
      ),
    ));
    final text = tester.widget<Text>(find.text('Solid name'));
    expect(text.style!.color, const Color(0xFFABCDEF));
  });
}
