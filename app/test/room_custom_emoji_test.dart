// Client 31/10 — emoji lists from the dashboard show first in the room picker.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/widgets/room/room_emoji.dart';

void main() {
  test('parses the server lists, skipping broken rows', () {
    final lists = RoomCustomEmoji.parse([
      {
        'id': 4,
        'nameAr': 'خاص',
        'imageUrl': '/assets/icons/a.webp',
        'emojis': [
          {'id': 7, 'name': 'قلب', 'imageUrl': '/assets/icons/7.gif'},
          {'id': 'x', 'imageUrl': '/bad'},
        ],
      },
      'junk',
    ]);
    expect(lists, hasLength(1));
    expect(lists.single.id, 'c:list:4');
    expect(lists.single.label, 'خاص');
    expect(lists.single.emojis.map((e) => e.id), ['c:7']);
    expect(lists.single.emojis.single.imageUrl, '/assets/icons/7.gif');
    expect(lists.single.emojis.single.isGame, isFalse);
  });

  test('a site-relative upload is loaded from the server root', () {
    expect(roomEmojiImageUrl('https://x.test/a.gif'), 'https://x.test/a.gif');
    expect(roomEmojiImageUrl('/assets/icons/a.gif'), endsWith('/assets/icons/a.gif'));
    expect(roomEmojiImageUrl('/assets/icons/a.gif'), startsWith('http'));
  });

  testWidgets('the picker opens on the dashboard list and picks its emoji', (tester) async {
    RoomCustomEmoji.debugSet(RoomCustomEmoji.parse([
      {
        'id': 1,
        'nameAr': 'قائمتي',
        'emojis': [
          {'id': 9, 'name': 'نجمة', 'imageUrl': 'https://x.test/9.gif'},
        ],
      },
    ]));
    RoomEmojiDef? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => RoomEmojiPicker.show(context, onPick: (e) => picked = e),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('قائمتي'), findsOneWidget);
    expect(find.text('نجمة'), findsOneWidget);
    await tester.tap(find.text('نجمة'));
    expect(picked?.id, 'c:9');
  });
}
