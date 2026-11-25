import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../services/socket_service.dart';
import '../../gifts/models/gift.dart';
import '../../gifts/widgets/lucky_winner_card.dart';
import '../app_network_image.dart';

/// Shared room + app-wide game stream; only removes its own socket handlers.
class RoomGameWins {
  static late final StreamController<GameWinAnnouncement> _controller =
      StreamController<GameWinAnnouncement>.broadcast(
          onListen: _bind, onCancel: _unbind);
  static Stream<GameWinAnnouncement> get stream => _controller.stream;
  static void _receive(dynamic data) {
    if (data is Map) {
      final win = GameWinAnnouncement.fromMap(data);
      if (win.coins > 0) _controller.add(win);
    }
  }

  static void _bind() {
    SocketService().on('game_win', _receive);
    SocketService().on('game_win_broadcast', _receive);
  }

  static void _unbind() {
    SocketService().off('game_win', _receive);
    SocketService().off('game_win_broadcast', _receive);
  }
}

class GameWinAnnouncement {
  GameWinAnnouncement.fromMap(Map d)
      : userId = (d['userId'] as num?)?.toInt() ?? 0,
        roomId = (d['roomId'] as num?)?.toInt(),
        name = (d['name'] ?? tr('لاعب', 'Player')).toString(),
        game =
            (d['gameName'] ?? d['gameId'] ?? d['game'] ?? tr('اللعبة', 'Game'))
                .toString(),
        avatar = (d['avatarUrl'] ?? d['avatar'])?.toString(),
        icon = (d['gameIconUrl'] ?? d['iconUrl'])?.toString(),
        coins = ((d['winCoins'] ?? d['prize']) as num?)?.toInt() ?? 0,
        multiplier = (d['multiplier'] ?? d['x']) as num?,
        at = DateTime.tryParse((d['timestamp'] ?? d['at'] ?? '').toString()) ??
            DateTime.now(),
        eventId = d['id']?.toString();
  final int userId, coins;
  final int? roomId;
  final String name, game;
  final String? avatar, icon, eventId;
  final num? multiplier;
  final DateTime at;
  String get key =>
      'game:${eventId ?? "$userId:$game:$coins:${at.millisecondsSinceEpoch}"}';
}

/// Reuses the winner card's follow, message and trail actions for game winners.
Future<void> showGameWinnerCard(BuildContext context, GameWinAnnouncement w,
    {int? myUserId}) {
  return showLuckyWinnerCard(
      context,
      LuckyRollEvent(
          rollId: 0,
          senderId: w.userId,
          senderName: w.name,
          senderAvatarUrl: w.avatar,
          recipientId: 0,
          roomId: w.roomId,
          giftName: w.game,
          giftIconUrl: w.icon,
          giftCoins: 0,
          hostCoins: 0,
          multiplier: w.multiplier?.toInt() ?? 0,
          payoutCoins: w.coins,
          ts: w.at),
      myUserId: myUserId,
      displayMultiplier: w.multiplier,
      winLabel: tr('ربح في ${w.game}', 'Won in ${w.game}'));
}

/// Payout grade of a win card (client 25/11): 0 up to x10, 1 for x11–x99,
/// 2 from x100. Same cut-offs as LuckyWinBanner.
int winCardGrade(num? multiplier) {
  final m = multiplier ?? 0;
  return m >= 100 ? 2 : (m > 10 ? 1 : 0);
}

/// The card's frame: [simple] for grade 0, thick gold with a soft glow for
/// grade 1, purple/red with a gold border and a strong glow for grade 2.
/// Static on purpose: no animation, no assets.
BoxDecoration winCardDecoration(int grade, BorderRadius radius, BoxDecoration simple) {
  if (grade == 0) return simple;
  final top = grade == 2;
  return BoxDecoration(
    gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: top
            ? const [Color(0xFF3B0A6B), Color(0xFF8E1450), Color(0xFFB3122E)]
            : const [Color(0xFF4A2504), Color(0xFF99600E), Color(0xFF3D1C03)]),
    borderRadius: radius,
    border: Border.all(color: const Color(0xFFFFD54F), width: top ? 2 : 2.5),
    boxShadow: top
        ? const [
            BoxShadow(color: Color(0xCCFF2D6F), blurRadius: 16, spreadRadius: 1),
            BoxShadow(color: Color(0x99FFD54F), blurRadius: 7),
          ]
        : const [BoxShadow(color: Color(0x88FFC107), blurRadius: 9)],
  );
}

/// Grade 2 adds a second, inner gold line (a double border).
Widget winCardInner(int grade, BorderRadius radius, EdgeInsets padding, Widget child) {
  if (grade < 2) return Padding(padding: padding, child: child);
  return Padding(
    padding: const EdgeInsets.all(2),
    child: DecoratedBox(
      decoration: BoxDecoration(
          borderRadius: radius, border: Border.all(color: const Color(0xFFFFE8A3))),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class RoomWinAnnouncement extends StatelessWidget {
  const RoomWinAnnouncement({super.key, this.lucky, this.game, this.myUserId});
  final LuckyRollEvent? lucky;
  final GameWinAnnouncement? game;
  final int? myUserId;
  @override
  Widget build(BuildContext context) {
    final name = lucky?.senderName ?? game?.name ?? tr('مستخدم', 'User');
    final avatar = lucky?.senderAvatarUrl ?? game?.avatar;
    final coins = lucky?.payoutCoins ?? game!.coins;
    final title =
        lucky != null ? tr('الهدية المحظوظة', 'Lucky gift') : game!.game;
    final multiplier = lucky?.multiplier ?? game?.multiplier;
    final grade = winCardGrade(multiplier);
    final radius = BorderRadius.circular(18);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => lucky != null
                    ? showLuckyWinnerCard(context, lucky!, myUserId: myUserId)
                    : showGameWinnerCard(context, game!, myUserId: myUserId),
                child: Ink(
                    decoration: winCardDecoration(
                        grade,
                        radius,
                        BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF155B66), Color(0xFF512885)]),
                            borderRadius: radius,
                            border: Border.all(color: const Color(0x667DE4DA)))),
                    child: winCardInner(grade, radius, const EdgeInsets.all(10),
                        Row(textDirection: TextDirection.rtl, children: [
                      ClipOval(
                          child: avatar?.isNotEmpty == true
                              ? AppNetworkImage(avatar!,
                                  width: 32, height: 32, fit: BoxFit.cover)
                              : const Icon(Icons.person,
                                  size: 32, color: Colors.white70)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              tr('مبروك $name ربح $coins عملة في $title',
                                  'Congratulations $name won $coins coins in $title'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600))),
                      if (grade == 2) ...[
                        const SizedBox(width: 6),
                        const Text('👑', style: TextStyle(fontSize: 20)),
                      ],
                      if (multiplier != null && multiplier > 0) ...[
                        const SizedBox(width: 8),
                        Flexible(
                            child: FittedBox(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                              Text('${multiplier}x',
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                      color: Color(0xFFFFD777),
                                      fontSize: 25,
                                      fontWeight: FontWeight.w900)),
                              Text(tr('مرات', 'Times'),
                                  style: const TextStyle(
                                      color: Color(0xFFFFE8B0), fontSize: 9)),
                            ]))),
                      ],
                    ]))))));
  }
}
