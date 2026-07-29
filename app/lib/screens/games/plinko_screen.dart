import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/plinko_repository.dart';

/// بلينكو — Plinko.
///
/// The server settles every drop before the ball moves: it returns the peg-by-peg
/// path, the landing slot and the payout, and this screen replays that path. The
/// animation is therefore decorative — it can never change where a ball lands.
class PlinkoScreen extends StatefulWidget {
  const PlinkoScreen({super.key});

  @override
  State<PlinkoScreen> createState() => _PlinkoScreenState();
}

class _PlinkoScreenState extends State<PlinkoScreen>
    with SingleTickerProviderStateMixin {
  final _repo = PlinkoRepository();

  late final AnimationController _ticker;

  PlinkoLayout? _layout;
  int _balance = 0;
  List<PlinkoDrop> _history = const [];

  String _risk = 'medium';
  int _rows = 16;
  int _bet = 100;

  bool _loading = true;
  String? _error;

  /// Balls currently falling. Each carries the server's path and its own start
  /// time, so several can be in flight at once without interfering.
  final List<_Ball> _balls = [];

  /// Slot index → time the slot last lit up, for the landing flash.
  final Map<int, Duration> _slotFlash = {};

  bool _autoBetting = false;
  int _autoRemaining = 0;

  @override
  void initState() {
    super.initState();
    // A free-running clock rather than one controller per ball: dropping a
    // dozen balls in a row should not spawn a dozen controllers.
    _ticker =
        AnimationController(vsync: this, duration: const Duration(days: 1))
          ..repeat();
    _ticker.addListener(_onTick);
    _load();
  }

  @override
  void dispose() {
    _ticker.removeListener(_onTick);
    _ticker.dispose();
    super.dispose();
  }

  Duration get _now => _ticker.lastElapsedDuration ?? Duration.zero;

  void _onTick() {
    if (_balls.isEmpty) return;

    final now = _now;
    final landed = <_Ball>[];
    for (final ball in _balls) {
      if (now - ball.startedAt >= ball.duration) landed.add(ball);
    }

    if (landed.isNotEmpty) {
      for (final ball in landed) {
        _slotFlash[ball.drop.slot] = now;
        _balls.remove(ball);
        _announce(ball.drop);
      }
    }

    // The board redraws every frame while anything is in flight or flashing.
    if (mounted) setState(() {});
  }

  void _announce(PlinkoDrop drop) {
    if (!mounted) return;
    if (drop.multiplier >= 10) HapticFeedback.mediumImpact();

    setState(() => _history = [drop, ..._history].take(30).toList());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _repo.fetchState();
      if (!mounted) return;
      setState(() {
        _layout = state.layout;
        _balance = state.balance;
        _history = state.history;
        _rows = _rows.clamp(state.layout.minRows, state.layout.maxRows);
        _bet = _bet.clamp(state.layout.minBet, state.layout.maxBet);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _drop() async {
    final layout = _layout;
    if (layout == null) return;

    if (_bet > _balance) {
      _toast('رصيدك لا يكفي');
      _stopAuto();
      return;
    }

    HapticFeedback.selectionClick();
    try {
      final result = await _repo.drop(risk: _risk, rows: _rows, amount: _bet);
      if (!mounted) return;
      setState(() {
        _balance = result.balance;
        _balls.add(_Ball(drop: result.drop, startedAt: _now, risk: _risk));
      });
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString());
      _stopAuto();
    }
  }

  /// Auto-bet: fires drops back to back with a short gap so the balls stagger
  /// down the board instead of overlapping into one blob.
  Future<void> _runAuto(int count) async {
    setState(() {
      _autoBetting = true;
      _autoRemaining = count;
    });

    while (mounted && _autoBetting && _autoRemaining > 0) {
      await _drop();
      if (!mounted || !_autoBetting) break;
      setState(() => _autoRemaining--);
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }

    if (mounted) _stopAuto();
  }

  void _stopAuto() {
    if (!mounted) return;
    setState(() {
      _autoBetting = false;
      _autoRemaining = 0;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: const Color(0xFF3A0A16),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07030F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: const Text('بلينكو',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text('$_balance',
                    style: const TextStyle(
                        color: Color(0xFFFFC107),
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(width: 4),
                const Text('🪙', style: TextStyle(fontSize: 16)),
              ]),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC107)))
            : _error != null
                ? _errorView()
                : _body(),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ]),
      );

  Widget _body() {
    final layout = _layout!;
    final multipliers = layout.multipliers(_risk, _rows);

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [Color(0xFF1B0B3A), Color(0xFF07030F)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          _historyBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: LayoutBuilder(
                builder: (context, constraints) => CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _PlinkoPainter(
                    rows: _rows,
                    multipliers: multipliers,
                    balls: _balls,
                    now: _now,
                    slotFlash: _slotFlash,
                  ),
                ),
              ),
            ),
          ),
          _bettingPanel(layout),
        ]),
      ),
    );
  }

  Widget _historyBar() {
    if (_history.isEmpty) return const SizedBox(height: 34);
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final drop = _history[i];
          final color = _slotColor(drop.multiplier);
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Text(
              '${_fmt(drop.multiplier)}x',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _bettingPanel(PlinkoLayout layout) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF120A26),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          _stepper('½', () => _setBet((_bet / 2).round(), layout)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text('$_bet 🪙',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 8),
          _stepper('2×', () => _setBet(_bet * 2, layout)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _riskPicker()),
          const SizedBox(width: 10),
          Expanded(child: _rowsPicker(layout)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _autoBetting ? null : _drop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFF00E676).withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('أسقط الكرة',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _autoBetting ? _stopAuto : _openAutoSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      _autoBetting ? const Color(0xFFFF5252) : Colors.white,
                  side: BorderSide(
                      color: _autoBetting
                          ? const Color(0xFFFF5252)
                          : Colors.white24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_autoBetting ? 'إيقاف ($_autoRemaining)' : 'تلقائي',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _stepper(String label, VoidCallback onTap) => SizedBox(
        width: 52,
        height: 42,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            side: const BorderSide(color: Colors.white24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );

  void _setBet(int value, PlinkoLayout layout) {
    setState(() => _bet = value.clamp(layout.minBet, layout.maxBet));
  }

  Widget _riskPicker() {
    const options = [
      ('low', 'منخفض', '🛡️', Color(0xFF00E676)),
      ('medium', 'متوسط', '⚖️', Color(0xFFFFC107)),
      ('high', 'عالٍ', '🔥', Color(0xFFFF5252)),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: options.map((o) {
          final selected = _risk == o.$1;
          return Expanded(
            child: GestureDetector(
              onTap: _autoBetting ? null : () => setState(() => _risk = o.$1),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? o.$4.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected ? o.$4 : Colors.transparent, width: 1),
                ),
                child: Text(o.$3, style: const TextStyle(fontSize: 15)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _rowsPicker(PlinkoLayout layout) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Text('$_rows صف',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFFFFC107),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFFFC107),
              ),
              child: Slider(
                value: _rows.toDouble(),
                min: layout.minRows.toDouble(),
                max: layout.maxRows.toDouble(),
                divisions: layout.maxRows - layout.minRows,
                onChanged: _autoBetting || _balls.isNotEmpty
                    ? null
                    : (v) => setState(() => _rows = v.round()),
              ),
            ),
          ),
        ]),
      );

  void _openAutoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF120A26),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('عدد الكرات',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [5, 10, 25, 50, 100].map((n) {
                return SizedBox(
                  width: 74,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _runAuto(n);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B21A8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('$n'),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────────────────────

/// A ball replaying a settled drop.
class _Ball {
  _Ball({required this.drop, required this.startedAt, required this.risk});

  final PlinkoDrop drop;
  final Duration startedAt;
  final String risk;

  /// Longer boards take proportionally longer, so the per-peg pace stays even.
  Duration get duration => Duration(milliseconds: 170 * drop.rows);

  Color get color => switch (risk) {
        'low' => const Color(0xFF00E676),
        'high' => const Color(0xFFFF5252),
        _ => const Color(0xFFFFC107),
      };
}

/// Multiplier colouring: green through yellow and orange to deep red as the
/// payout climbs, so the edges read as the dangerous, valuable slots.
Color _slotColor(double multiplier) {
  if (multiplier >= 100) return const Color(0xFFB71C1C);
  if (multiplier >= 25) return const Color(0xFFE53935);
  if (multiplier >= 9) return const Color(0xFFFF7043);
  if (multiplier >= 3) return const Color(0xFFFFA726);
  if (multiplier >= 1.1) return const Color(0xFFFFD54F);
  if (multiplier >= 1) return const Color(0xFFDCE775);
  return const Color(0xFF8BC34A);
}

String _fmt(double m) => m >= 10
    ? m.toStringAsFixed(0)
    : m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1);

class _PlinkoPainter extends CustomPainter {
  _PlinkoPainter({
    required this.rows,
    required this.multipliers,
    required this.balls,
    required this.now,
    required this.slotFlash,
  });

  final int rows;
  final List<double> multipliers;
  final List<_Ball> balls;
  final Duration now;
  final Map<int, Duration> slotFlash;

  static const _flashDuration = Duration(milliseconds: 500);

  @override
  void paint(Canvas canvas, Size size) {
    final slotHeight = math.min(34.0, size.height * 0.09);
    final boardHeight = size.height - slotHeight - 10;

    // Spacing is whichever of width or height is the binding constraint, so the
    // triangle always fits without clipping on short or narrow screens.
    final spacingX = size.width / (rows + 2);
    final spacingY = boardHeight / (rows + 1);
    final spacing = math.min(spacingX, spacingY);

    final centerX = size.width / 2;
    final topY = (boardHeight - spacing * rows) / 2 + spacing * 0.5;

    _paintPegs(canvas, centerX, topY, spacing);
    _paintSlots(canvas, size, slotHeight, spacing, centerX);
    _paintBalls(canvas, centerX, topY, spacing, boardHeight);
  }

  Offset _peg(
          int row, int index, double centerX, double topY, double spacing) =>
      Offset(
        centerX + (index - row / 2) * spacing,
        topY + row * spacing,
      );

  void _paintPegs(Canvas canvas, double centerX, double topY, double spacing) {
    final radius = math.max(2.0, spacing * 0.085);
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final peg = Paint()..color = Colors.white.withValues(alpha: 0.92);

    // Row r carries r+1 pegs; row 0 is the single peg under the drop point.
    for (var r = 0; r < rows; r++) {
      for (var i = 0; i <= r; i++) {
        final p = _peg(r, i, centerX, topY, spacing);
        canvas.drawCircle(p, radius * 2.1, glow);
        canvas.drawCircle(p, radius, peg);
      }
    }
  }

  void _paintSlots(Canvas canvas, Size size, double slotHeight, double spacing,
      double centerX) {
    final count = multipliers.length;
    final width = math.min(spacing * 0.94, size.width / count - 2);
    final y = size.height - slotHeight;

    for (var i = 0; i < count; i++) {
      final multiplier = multipliers[i];
      final color = _slotColor(multiplier);
      final x = centerX + (i - (count - 1) / 2) * spacing;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(x, y + slotHeight / 2),
            width: width,
            height: slotHeight),
        const Radius.circular(6),
      );

      // A slot stays lit for a moment after a ball lands in it.
      final flashedAt = slotFlash[i];
      var flash = 0.0;
      if (flashedAt != null) {
        final elapsed =
            (now - flashedAt).inMilliseconds / _flashDuration.inMilliseconds;
        if (elapsed >= 0 && elapsed <= 1) flash = 1 - elapsed;
      }

      if (flash > 0) {
        canvas.drawRRect(
          rect.inflate(4 * flash),
          Paint()
            ..color = color.withValues(alpha: 0.7 * flash)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * flash),
        );
      }

      canvas.drawRRect(
          rect, Paint()..color = color.withValues(alpha: 0.85 + 0.15 * flash));

      final label = TextPainter(
        text: TextSpan(
          text: '${_fmt(multiplier)}x',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontSize: math.max(7.0, width * 0.32),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      label.paint(
        canvas,
        Offset(x - label.width / 2, y + slotHeight / 2 - label.height / 2),
      );
    }
  }

  void _paintBalls(Canvas canvas, double centerX, double topY, double spacing,
      double boardHeight) {
    final radius = math.max(3.0, spacing * 0.28);

    for (final ball in balls) {
      final elapsed = (now - ball.startedAt).inMilliseconds;
      final progress = (elapsed / ball.duration.inMilliseconds).clamp(0.0, 1.0);
      final position =
          _ballPosition(ball, progress, centerX, topY, spacing, boardHeight);

      canvas.drawCircle(
        position,
        radius * 2.4,
        Paint()
          ..color = ball.color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(position, radius, Paint()..color = ball.color);
      // Specular dot: sells the ball as a sphere rather than a flat disc.
      canvas.drawCircle(
        position.translate(-radius * 0.3, -radius * 0.35),
        radius * 0.32,
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }
  }

  /// Walks the server's path. Between two pegs the ball moves linearly sideways
  /// and takes a small hop upward, which reads as a bounce without needing a
  /// physics solver — and keeps the landing slot exactly where the server said.
  Offset _ballPosition(_Ball ball, double progress, double centerX, double topY,
      double spacing, double boardHeight) {
    final directions = ball.drop.directions;
    final total = directions.length;
    if (total == 0) {
      return Offset(centerX, topY + boardHeight * progress);
    }

    final travelled = progress * total;
    final step = travelled.floor().clamp(0, total - 1);
    final frac = (travelled - step).clamp(0.0, 1.0);

    // Cumulative rights so far = horizontal peg index at this row.
    var index = 0;
    for (var i = 0; i < step; i++) {
      index += directions[i];
    }

    final from = _peg(step, index, centerX, topY, spacing);
    final nextIndex = index + directions[step];
    final to = step + 1 < total
        ? _peg(step + 1, nextIndex, centerX, topY, spacing)
        : Offset(
            centerX + (nextIndex - (total) / 2) * spacing,
            topY + total * spacing,
          );

    final hop = math.sin(frac * math.pi) * spacing * 0.18;
    return Offset(
      from.dx + (to.dx - from.dx) * frac,
      from.dy + (to.dy - from.dy) * frac - hop,
    );
  }

  @override
  bool shouldRepaint(_PlinkoPainter old) =>
      old.now != now ||
      old.rows != rows ||
      old.balls.length != balls.length ||
      old.multipliers != multipliers;
}
