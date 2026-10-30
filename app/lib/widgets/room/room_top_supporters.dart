import 'package:flutter/material.dart';
import '../../services/socket_service.dart';
import '../../l10n/tr.dart';
import '../app_network_image.dart';

class RoomTopSupporters extends StatelessWidget {
  const RoomTopSupporters({super.key, required this.items, required this.onTap});
  final List<RoomParticipant> items;
  final ValueChanged<RoomParticipant> onTap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    textDirection: TextDirection.ltr,
    children: [
      for (var i = 0; i < items.length && i < 2; i++)
        Semantics(
          button: true,
          label: tr('الداعم', 'Supporter') + ' #${i + 1}: ${items[i].name}',
          child: InkWell(
            onTap: () => onTap(items[i]),
            child: SizedBox(
              width: 64, height: 54,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(64, 44), painter: _WingFrame(gold: i == 0)),
                CircleAvatar(
                  radius: 16,
                  backgroundImage: (items[i].avatar ?? '').isNotEmpty
                      ? appImage(items[i].avatar!, 32) : null,
                  child: (items[i].avatar ?? '').isEmpty ? const Icon(Icons.person, size: 20) : null,
                ),
                if (i == 0)
                  const Positioned(top: 0, child: CustomPaint(
                      size: Size(17, 12), painter: _Crown())),
              ]),
            ),
          ),
        ),
    ],
  );
}

class _Crown extends CustomPainter {
  const _Crown();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(1, 2)..lineTo(5, 5)..lineTo(8.5, 0)
      ..lineTo(12, 5)..lineTo(16, 2)..lineTo(14, 11)..lineTo(3, 11)..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD86B));
  }
  @override
  bool shouldRepaint(covariant _Crown oldDelegate) => false;
}

class _WingFrame extends CustomPainter {
  const _WingFrame({required this.gold});
  final bool gold;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = gold
        ? const [Color(0xFFFFD86B), Color(0xFFB8860B)]
        : const [Color(0xFFF5F7FA), Color(0xFF8995A5)];
    final paint = Paint()..shader = LinearGradient(colors: colors,
        begin: Alignment.topCenter, end: Alignment.bottomCenter)
        .createShader(Offset.zero & size);
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 19, paint);
    // Feathered wing silhouettes, mirrored around the avatar.
    for (final direction in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(direction, 1);
      final wing = Path()
        ..moveTo(17, -7)
        ..quadraticBezierTo(24, -8, 31, -17)
        ..quadraticBezierTo(32, -8, 26, -3)
        ..lineTo(31, -6)
        ..quadraticBezierTo(29, 3, 24, 5)
        ..lineTo(28, 3)
        ..quadraticBezierTo(25, 12, 17, 12)
        ..close();
      canvas.drawPath(wing, Paint()..color = colors.last);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WingFrame oldDelegate) => gold != oldDelegate.gold;
}
