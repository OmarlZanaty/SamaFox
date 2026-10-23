import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/widgets/room/room_header_glass.dart';

void main() {
  testWidgets('room header keeps its labels and tap without a backdrop blur',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: RoomHeaderGlass(
            name: 'Test room',
            idLabel: 'ID: 123456',
            onTap: () => taps++,
          ),
        ),
      ),
    ));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.text('Test room'), findsOneWidget);
    expect(find.text('ID: 123456'), findsOneWidget);
    await tester.tap(find.text('Test room'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
