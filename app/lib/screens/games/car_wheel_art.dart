import 'dart:math';
import 'package:flutter/material.dart';
import 'car_wheel_engine.dart';

const cwBlack = Color(0xFF07080D);
const cwNavy = Color(0xFF16102B);
const cwPurple = Color(0xFF6837A5);
const cwPurpleDark = Color(0xFF281052);
const cwGold = Color(0xFFF5BD45);
const cwGoldLight = Color(0xFFFFE7A2);
const cwMuted = Color(0xFFC1B1D3);
const cwPink = Color(0xFFE62757);
const carWheelArt = 'assets/images/games/car_wheel';

/// Commissioned cutouts can arrive later; every asset has a painted fallback.
Widget carWheelImage(String name, Widget fallback,
        {double? width, double? height,}) =>
    Image.asset('$carWheelArt/$name.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,);

class CarWheelEmblem extends StatelessWidget {
  final String segment;
  final double size;
  const CarWheelEmblem({super.key, required this.segment, this.size = 36});
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: carWheelImage(
          'emblem_$segment', CustomPaint(painter: _EmblemPainter(segment)),),);
}

/// Original geometric badges from CAR_WHEEL_ARTWORK_BRIEF.md, never car logos.
class _EmblemPainter extends CustomPainter {
  final String keyName;
  _EmblemPainter(this.keyName);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final fill = Paint()..color = const Color(0xFF191421);
    final edge = Paint()
      ..color = cwGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const silver = Color(0xFFE0E4F2);
    Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
    Path regular(int n, double r, {double angle = -pi / 2}) => polygon([
          for (var i = 0; i < n; i++)
            Offset(50 + r * cos(angle + i * 2 * pi / n),
                50 + r * sin(angle + i * 2 * pi / n),),
        ]);
    void shape(Path p) {
      canvas.drawPath(p, fill);
      canvas.drawPath(p, edge);
    }

    void letter(String value, Color color) {
      final t = TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  color: color, fontSize: 51, fontWeight: FontWeight.w900,),),
          textDirection: TextDirection.ltr,)
        ..layout();
      t.paint(canvas, Offset(50 - t.width / 2, 50 - t.height / 2));
    }

    final shield = polygon(const [
      Offset(15, 12),
      Offset(85, 12),
      Offset(80, 65),
      Offset(50, 91),
      Offset(20, 65),
    ]);
    switch (keyName) {
      case 'aurelia':
        fill.color = const Color(0xFF9F1837);
        shape(shield);
        letter('A', cwGold);
      case 'bavaro':
        edge.color = silver;
        shape(regular(6, 43));
        for (final x in [28.0, 50.0, 72.0]) {
          canvas.drawPath(
              polygon([
                Offset(x, 36),
                Offset(x + 9, 50),
                Offset(x, 64),
                Offset(x - 9, 50),
              ]),
              Paint()..color = silver,);
        }
      case 'stellaro':
        fill.color = const Color(0xFF78152F);
        shape(Path()..addOval(const Rect.fromLTWH(7, 7, 86, 86)));
        canvas.drawPath(
            polygon([
              for (var i = 0; i < 16; i++)
                Offset(50 + (i.isEven ? 33 : 15) * sin(i * pi / 8),
                    50 - (i.isEven ? 33 : 15) * cos(i * pi / 8),),
            ]),
            Paint()..color = cwGold,);
      case 'ferrarion':
        fill.color = cwGold;
        edge.color = const Color(0xFF80132D);
        shape(Path()..addOval(const Rect.fromLTWH(5, 15, 90, 70)));
        canvas.drawPath(
            polygon(const [
              Offset(25, 72),
              Offset(38, 32),
              Offset(82, 26),
              Offset(66, 43),
              Offset(48, 43),
              Offset(45, 51),
              Offset(70, 47),
              Offset(57, 62),
              Offset(40, 61),
            ]),
            Paint()..color = edge.color,);
      case 'lambrex':
        shape(shield);
        canvas.drawPath(
            polygon(const [
              Offset(28, 28),
              Offset(64, 32),
              Offset(80, 46),
              Offset(62, 47),
              Offset(53, 71),
              Offset(36, 61),
              Offset(46, 44),
            ]),
            Paint()..color = cwGold,);
        canvas.drawCircle(const Offset(60, 40), 3, Paint()..color = cwBlack);
      case 'voltara':
        fill.color = const Color(0xFF345675);
        edge.color = silver;
        shape(Path()..addOval(const Rect.fromLTWH(7, 7, 86, 86)));
        canvas.drawPath(
            polygon(const [
              Offset(23, 25),
              Offset(45, 50),
              Offset(52, 34),
              Offset(77, 22),
              Offset(55, 75),
              Offset(44, 80),
              Offset(35, 48),
            ]),
            Paint()..color = silver,);
      case 'porsenna':
        fill.color = const Color(0xFFB32642);
        shape(shield);
        canvas.save();
        canvas.clipPath(shield);
        canvas.drawLine(
            const Offset(7, 76),
            const Offset(89, 12),
            Paint()
              ..color = cwGold
              ..strokeWidth = 14,);
        canvas.restore();
        letter('P', cwGoldLight);
      case 'bentara':
        edge.color = silver;
        shape(Path()..addOval(const Rect.fromLTWH(7, 7, 86, 86)));
        for (var i = 0; i < 16; i++) {
          final a = i * pi / 8;
          canvas.save();
          canvas.translate(50 + 35 * cos(a), 50 + 35 * sin(a));
          canvas.rotate(a + .5);
          canvas.drawOval(
              const Rect.fromLTWH(-7, -2, 14, 4), Paint()..color = silver,);
          canvas.restore();
        }
        letter('8', silver);
      default:
        shape(regular(8, 40));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => keyName != old.keyName;
}

class CarWheelChip extends StatelessWidget {
  final int amount;
  final double size;
  final bool selected, glow;
  const CarWheelChip(
      {super.key,
      required this.amount,
      this.size = 48,
      this.selected = false,
      this.glow = false,});
  @override
  Widget build(BuildContext context) {
    final name = switch (amount) {
      100 => '100',
      1000 => '1k',
      10000 => '10k',
      _ => '100k'
    };
    return AnimatedScale(
        scale: selected ? 1.12 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              if (selected || glow)
                BoxShadow(
                    color: cwGold.withValues(alpha: .8),
                    blurRadius: 12,
                    spreadRadius: 2,),
            ],),
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                  child: carWheelImage('chip_$name',
                      CustomPaint(painter: _ChipPainter(amount)),),),
              Text(carWheelCompact(amount),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: size * .23,
                      fontWeight: FontWeight.w900,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 3),
                      ],),),
            ],),),);
  }
}

class _ChipPainter extends CustomPainter {
  final int amount;
  _ChipPainter(this.amount);
  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero), r = s.width / 2;
    final color = switch (amount) {
      100 => const Color(0xFF1FAF49),
      1000 => const Color(0xFF1989D7),
      10000 => const Color(0xFF8A3DC3),
      _ => const Color(0xFFBB2D43)
    };
    c.drawCircle(center, r, Paint()..color = color);
    for (var i = 0; i < 12; i++) {
      c.drawArc(
          Rect.fromCircle(center: center, radius: r * .84),
          i * pi / 6,
          .25,
          false,
          Paint()
            ..color = amount == 100000 ? cwGold : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .15,);
    }
    c.drawCircle(
        center,
        r * .65,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,);
  }

  @override
  bool shouldRepaint(_ChipPainter old) => amount != old.amount;
}

/// The disk rotates as one: wedges, labels, totals and chips are its children.
class CarWheelDiskPainter extends CustomPainter {
  final String? winner;
  final double glow;
  CarWheelDiskPainter({this.winner, this.glow = 0});
  @override
  void paint(Canvas c, Size size) {
    final center = size.center(Offset.zero), r = size.width * .455;
    const colors = [Color(0xFFE62757), Color(0xFFA7133B), Color(0xFFF13B6B)];
    for (var i = 0; i < 8; i++) {
      final start = -pi / 2 + (i - .5) * carWheelSegmentAngle;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: r), start,
            carWheelSegmentAngle, false,)
        ..close();
      c.drawPath(path, Paint()..color = colors[i % 3]);
      c.drawPath(
          path,
          Paint()
            ..color = Colors.white30
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,);
      if (carWheelSegments[i].key == winner) {
        c.drawPath(
            path, Paint()..color = cwGold.withValues(alpha: .13 + glow * .25),);
        c.drawPath(
            path,
            Paint()
              ..color = cwGold.withValues(alpha: .5 + glow * .5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,);
      }
    }
  }

  @override
  bool shouldRepaint(CarWheelDiskPainter old) =>
      winner != old.winner || glow != old.glow;
}

class CarWheelRimPainter extends CustomPainter {
  const CarWheelRimPainter();
  @override
  void paint(Canvas c, Size s) {
    final p = s.center(Offset.zero), r = s.width / 2;
    c.drawCircle(
        p,
        r * .95,
        Paint()
          ..color = cwPurple
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .08,);
    c.drawCircle(
        p,
        r * .92,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .018
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),);
    c.drawCircle(
        p,
        r * .908,
        Paint()
          ..color = cwGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,);
    for (var i = 0; i < 32; i++) {
      c.drawCircle(p + Offset(sin(i * pi / 16), -cos(i * pi / 16)) * r * .963,
          r * .008, Paint()..color = cwGoldLight,);
    }
  }

  @override
  bool shouldRepaint(CarWheelRimPainter old) => false;
}

class CarWheelPointerPainter extends CustomPainter {
  const CarWheelPointerPainter();
  @override
  void paint(Canvas c, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    c.drawPath(path, Paint()..color = cwGold);
    c.drawCircle(
        Offset(s.width / 2, s.width / 3), s.width / 5, Paint()..color = cwPink,);
  }

  @override
  bool shouldRepaint(CarWheelPointerPainter old) => false;
}
