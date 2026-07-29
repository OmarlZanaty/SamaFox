import 'dart:math';

import 'package:flutter/material.dart';

/// The four bonus rounds of عجلة الحظ.
///
/// None of these decide anything: the server has already rolled the entire
/// outcome (backend/src/services/crazyWheel.service.ts) and hands it over in
/// the round state. These widgets replay that outcome — the coin lands on the
/// side the server chose, the puck bounces down the path the server generated,
/// the Crazy Time wheel stops on the segments the server picked.

const _gold = Color(0xFFFFD54F);

// ── Coin Flip ───────────────────────────────────────────────
class CoinFlipBonus extends StatefulWidget {
  /// `{red, blue, winner, multiplier}` as sent by the server.
  final Map<String, dynamic> data;
  const CoinFlipBonus({super.key, required this.data});

  @override
  State<CoinFlipBonus> createState() => _CoinFlipBonusState();
}

class _CoinFlipBonusState extends State<CoinFlipBonus> with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = (widget.data['red'] as num?)?.toInt() ?? 0;
    final blue = (widget.data['blue'] as num?)?.toInt() ?? 0;
    final winner = widget.data['winner']?.toString() ?? 'red';

    return _BonusShell(
      title: 'COIN FLIP',
      accent: const Color(0xFFE53935),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _multiplierPlate(red, const Color(0xFFD32F2F), winner == 'red'),
              _multiplierPlate(blue, const Color(0xFF1565C0), winner == 'blue'),
            ],
          ),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              // Spin down to a stop, then settle on the winning face. The
              // final half-turn is chosen so the winner's colour faces up.
              final t = Curves.easeOutCubic.transform(_flip.value);
              final turns = t * 6 + (winner == 'blue' ? 0.5 : 0.0);
              final angle = turns * pi;
              final showRed = (angle / pi).floor().isEven;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..setEntry(3, 2, 0.0015)..rotateX(angle),
                child: _coinFace(showRed ? const Color(0xFFD32F2F) : const Color(0xFF1565C0)),
              );
            },
          ),
          const SizedBox(height: 22),
          if (_flip.isCompleted || _flip.value > 0.9)
            Text(
              'x${winner == 'red' ? red : blue}',
              style: const TextStyle(color: _gold, fontSize: 34, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _coinFace(Color color) => Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withOpacity(0.95), color.withOpacity(0.55)]),
          border: Border.all(color: _gold, width: 4),
          boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 30)],
        ),
      );

  Widget _multiplierPlate(int value, Color color, bool isWinner) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(isWinner ? 0.95 : 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isWinner ? _gold : Colors.white24, width: isWinner ? 3 : 1),
        ),
        child: Text('x$value',
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
      );
}

// ── Cash Hunt ───────────────────────────────────────────────
class CashHuntBonus extends StatelessWidget {
  /// `{grid: [108 multipliers], symbols: [108 symbol ids]}`.
  final Map<String, dynamic> data;

  /// True during the pick window; false once the board is revealed.
  final bool picking;
  final int? myPick;
  final ValueChanged<int> onPick;

  const CashHuntBonus({
    super.key,
    required this.data,
    required this.picking,
    required this.myPick,
    required this.onPick,
  });

  static const _symbols = ['🦊', '💎', '🍀', '🔥', '⭐', '🎁'];

  @override
  Widget build(BuildContext context) {
    final grid = ((data['grid'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    final symbols = ((data['symbols'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();

    return _BonusShell(
      title: 'CASH HUNT',
      iconPath: 'assets/images/crazy/icon_cashhunt.png',
      accent: const Color(0xFF2E7D32),
      subtitle: picking ? 'اختر رمزًا واحدًا' : 'كُشف عن المضاعفات',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const columns = 12;
          const rows = 9; // 108 tiles
          // Size off whichever axis runs out first, or the board spills past
          // the panel and over the betting grid underneath.
          final byWidth = (constraints.maxWidth - (columns - 1) * 3) / columns;
          final byHeight = (constraints.maxHeight - (rows - 1) * 3) / rows;
          final tile = min(byWidth, byHeight.isFinite ? byHeight : byWidth);
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: List.generate(108, (i) {
              final mine = myPick == i;
              final revealed = !picking || mine;
              return GestureDetector(
                onTap: picking && myPick == null ? () => onPick(i) : null,
                child: Container(
                  width: tile,
                  height: tile,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: mine
                        ? _gold.withOpacity(0.85)
                        : Colors.white.withOpacity(revealed ? 0.10 : 0.16),
                    borderRadius: BorderRadius.circular(4),
                    border: mine ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: revealed && i < grid.length
                          ? Text('${grid[i]}',
                              style: TextStyle(
                                color: mine ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ))
                          : Text(_symbols[(i < symbols.length ? symbols[i] : 0) % _symbols.length]),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ── Pachinko ────────────────────────────────────────────────
class PachinkoBonus extends StatefulWidget {
  /// `{drops: [{slots, path, landed, value}], multiplier}`.
  final Map<String, dynamic> data;
  const PachinkoBonus({super.key, required this.data});

  @override
  State<PachinkoBonus> createState() => _PachinkoBonusState();
}

class _PachinkoBonusState extends State<PachinkoBonus> with SingleTickerProviderStateMixin {
  late final AnimationController _drop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..forward();
  int _dropIndex = 0;

  @override
  void initState() {
    super.initState();
    // Each DOUBLE re-drops the puck, so walk through the server's drop list.
    _drop.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final drops = (widget.data['drops'] as List?) ?? const [];
      if (_dropIndex < drops.length - 1) {
        setState(() => _dropIndex++);
        _drop.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drops = (widget.data['drops'] as List?) ?? const [];
    if (drops.isEmpty) return const SizedBox.shrink();
    final drop = Map<String, dynamic>.from(drops[_dropIndex.clamp(0, drops.length - 1)] as Map);
    final slots = ((drop['slots'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
    final path = ((drop['path'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();

    return _BonusShell(
      title: 'PACHINKO',
      iconPath: 'assets/images/crazy/icon_pachinko.png',
      accent: const Color(0xFFD81B60),
      subtitle: _dropIndex > 0 ? 'DOUBLE! كل المضاعفات تضاعفت' : null,
      child: AspectRatio(
        aspectRatio: 0.9,
        child: AnimatedBuilder(
          animation: _drop,
          builder: (context, _) => CustomPaint(
            painter: _PachinkoPainter(
              slots: slots,
              path: path,
              progress: Curves.easeIn.transform(_drop.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _PachinkoPainter extends CustomPainter {
  final List<int> slots;
  final List<int> path;
  final double progress;
  _PachinkoPainter({required this.slots, required this.path, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rows = path.length;
    if (rows == 0 || slots.isEmpty) return;

    final wallHeight = size.height * 0.78;
    final rowGap = wallHeight / (rows + 1);
    final colGap = size.width / (slots.length + 1);
    final peg = Paint()..color = Colors.white.withOpacity(0.65);

    // Peg field.
    for (var r = 0; r < rows; r++) {
      final y = rowGap * (r + 1);
      final offset = r.isEven ? 0.0 : colGap / 2;
      for (var x = offset; x < size.width; x += colGap) {
        canvas.drawCircle(Offset(x, y), 2.5, peg);
      }
    }

    // Slot labels along the bottom.
    for (var i = 0; i < slots.length; i++) {
      final x = colGap * (i + 1) - colGap / 2;
      final rect = Rect.fromLTWH(x, wallHeight, colGap - 2, size.height - wallHeight - 4);
      final isDouble = slots[i] == 0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = isDouble ? const Color(0xFFFFD54F) : const Color(0xFFD81B60).withOpacity(0.75),
      );
      _label(
        canvas,
        isDouble ? 'x2' : '${slots[i]}',
        rect.center,
        isDouble ? Colors.black : Colors.white,
        rect.width * 0.42,
      );
    }

    // The puck, walking the server's bounce path.
    final step = (progress * rows).clamp(0.0, rows.toDouble());
    final row = step.floor().clamp(0, rows - 1);
    final frac = step - row;
    var drift = 0.0;
    for (var r = 0; r < row; r++) {
      drift += path[r] * colGap / 2;
    }
    final nextDrift = drift + path[row] * colGap / 2 * frac;
    final puck = Offset(
      (size.width / 2 + nextDrift).clamp(6.0, size.width - 6),
      rowGap * step.clamp(0.0, rows.toDouble()),
    );
    canvas.drawCircle(puck, 9, Paint()..color = Colors.white);
    canvas.drawCircle(puck, 9, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFD54F));
  }

  void _label(Canvas canvas, String text, Offset center, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PachinkoPainter old) =>
      old.progress != progress || old.slots != slots || old.path != path;
}

// ── Crazy Time ──────────────────────────────────────────────
class CrazyTimeBonus extends StatelessWidget {
  /// `{spins: [{ring, landed}], multipliers: {blue, green, yellow}}`.
  final Map<String, dynamic> data;
  final bool picking;
  final String? myPick;
  final ValueChanged<String> onPick;

  const CrazyTimeBonus({
    super.key,
    required this.data,
    required this.picking,
    required this.myPick,
    required this.onPick,
  });

  static const _flappers = {
    'blue': Color(0xFF1E88E5),
    'green': Color(0xFF43A047),
    'yellow': Color(0xFFFDD835),
  };

  @override
  Widget build(BuildContext context) {
    final multipliers = (data['multipliers'] as Map?) ?? const {};

    return _BonusShell(
      title: 'CRAZY TIME',
      iconPath: 'assets/images/crazy/icon_crazytime.png',
      accent: const Color(0xFFC62828),
      subtitle: picking ? 'اختر القلاب الخاص بك' : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _flappers.entries.map((e) {
              final mine = myPick == e.key;
              final value = (multipliers[e.key] as num?)?.toInt();
              return GestureDetector(
                onTap: picking && myPick == null ? () => onPick(e.key) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 92,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: e.value.withOpacity(mine ? 0.95 : 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: mine ? _gold : Colors.white24, width: mine ? 3 : 1),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.arrow_drop_down, color: Colors.white, size: 34),
                      Text(
                        !picking && value != null ? 'x$value' : (mine ? 'اخترته' : '؟'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          if (!picking)
            const Text(
              'العجلة الضخمة توقفت — تُطبَّق المضاعفات الآن',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

// ── Shared chrome ───────────────────────────────────────────
class _BonusShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color accent;
  final Widget child;

  /// Commissioned game icon. Coin Flip has none yet, so it stays null and the
  /// header is just the wordmark.
  final String? iconPath;

  const _BonusShell({
    required this.title,
    required this.accent,
    required this.child,
    this.subtitle,
    this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withOpacity(0.35), const Color(0xFF0D0620)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.6), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconPath != null)
            SizedBox(
              height: 56,
              child: Image.asset(
                iconPath!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
              shadows: [Shadow(color: accent, blurRadius: 18)],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          Flexible(child: child),
        ],
      ),
    );
  }
}
