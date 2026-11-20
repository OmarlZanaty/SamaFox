import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/gifts/services/gift_socket_service.dart';
import 'package:samafox/widgets/room/room_gift_announcement_text.dart';

class _Socket implements GiftSocketService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final announcements = StreamController<GiftAnnouncement>.broadcast();
  @override
  Stream<GiftAnnouncement> get announcementStream => announcements.stream;
}

GiftAnnouncement _announcement(String name, {int roomId = 1}) => GiftAnnouncement(
    senderId: 2, senderName: name, giftName: 'Lamp', giftIconUrl: '',
    recipientCount: 3, roomId: roomId);

void main() {
  testWidgets('announcements are one small text line, queued and room-filtered',
      (tester) async {
    final socket = _Socket();
    addTearDown(socket.announcements.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 300,
      child: RoomGiftAnnouncementText(socket: socket, roomId: 1),
    ))));
    socket.announcements.add(_announcement('Other', roomId: 2));
    await tester.pump();
    expect(find.byType(Text), findsNothing);
    final first = _announcement('First');
    final second = _announcement('Second');
    socket.announcements.add(first);
    socket.announcements.add(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final line = tester.widget<Text>(find.text(first.text));
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    expect(line.style?.fontSize, 12);
    expect(find.text(second.text), findsNothing);
    expect(find.descendant(of: find.byType(RoomGiftAnnouncementText),
        matching: find.byType(DecoratedBox)), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(second.text), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
