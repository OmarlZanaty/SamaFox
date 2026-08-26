import 'dart:math' as math;
import 'dart:ui';

import '../../repositories/plinko_repository.dart';
import 'plinko_sim.dart';

/// Motion for a بلينكو ball.
///
/// The server has already decided the path, so this never simulates *where* the
/// ball goes — only how it gets there. Everything below is presentation: gravity
/// so the fall accelerates, an ease on the sideways kick off each peg, squash on
/// contact, spin, and a short trail.
class PlinkoBall {
  PlinkoBall({
    required this.drop,
    required this.startedAt,
    required this.risk,
  });

  final PlinkoDrop drop;
  final Duration startedAt;
  final String risk;

  /// Positions from recent frames, newest last, for the motion trail.
  final List<Offset> trail = [];

  /// Row whose peg was struck most recently — drives the tick sound and the
  /// peg flash. -1 until the first contact.
  int lastPegRow = -1;

  /// Latest frame, computed once by the frame loop and reused by the painter
  /// so the motion is never solved twice.
  BallFrame? frame;

  /// Solved ballistic path. Null until the board geometry is known, which is
  /// why [frameAt] is kept as the fallback for the first frame after a drop.
  PlinkoTrajectory? trajectory;

  /// Arc index last seen, so a fresh peg contact is detected exactly once.
  int lastArc = -1;

  /// Squash driven by real impact speed rather than a fixed curve: the harder
  /// the landing, the flatter the ball goes.
  double impactSquash = 1.0;

  /// Pixels per second, from the last two frames. Drives the motion blur:
  /// a fast object rendered as a crisp sprite reads as a stutter, not speed.
  Offset velocity = Offset.zero;

  Offset? _previous;
  Duration? _previousAt;

  void observe(BallFrame next, Duration at) {
    final prev = _previous;
    final prevAt = _previousAt;
    if (prev != null && prevAt != null) {
      final dt = (at - prevAt).inMicroseconds / 1e6;
      if (dt > 1e-4) {
        velocity = Offset(
          (next.position.dx - prev.dx) / dt,
          (next.position.dy - prev.dy) / dt,
        );
      }
    }
    _previous = next.position;
    _previousAt = at;
    frame = next;

    trail.add(next.position);
    if (trail.length > 10) trail.removeAt(0);
  }

  /// Slots still reachable from the current row — used to pulse the landing
  /// zone as the ball closes in. Every remaining peg can go either way, so the
  /// reachable set is a contiguous window.
  (int, int) reachableSlots(int rowsDone) {
    var lowest = 0;
    for (var i = 0; i < rowsDone && i < drop.directions.length; i++) {
      lowest += drop.directions[i];
    }
    final remaining = drop.rows - rowsDone;
    return (lowest, lowest + remaining);
  }

  /// Total fall time. Once the path is solved this is the simulation's own
  /// duration; before that it falls back to a fixed pace per row.
  Duration get duration {
    final solved = trajectory;
    if (solved != null) {
      return Duration(microseconds: (solved.totalSeconds * 1e6).round());
    }
    return Duration(milliseconds: 150 * drop.rows + 250);
  }

  /// Solves the ballistic path. Called once, as soon as board geometry exists.
  void solve(PlinkoTrajectory solved) {
    trajectory = solved;
  }

  /// Samples the solved path. Returns null when there is nothing solved yet.
  BallFrame? simulatedFrame(double seconds) {
    final solved = trajectory;
    if (solved == null) return null;

    final sample = solved.sampleAt(seconds);

    // Squash from the vertical speed at impact, easing out over the first part
    // of each arc — a hard landing flattens the ball more than a glancing one.
    final arc = solved.arcs[sample.arcIndex.toInt()];
    final local = seconds - arc.startSeconds;
    final entry = arc.velocity.dy.abs() / (arc.gravity * 0.35);
    final relax = (local / (arc.duration * 0.35)).clamp(0.0, 1.0);
    final squash = (1 - entry.clamp(0.0, 0.5)) * (1 - relax) + relax;
    final scaleY = (0.62 + 0.38 * squash).clamp(0.62, 1.0);

    return BallFrame(
      sample.position,
      (2 - scaleY) / scaleY,
      sample.rotation,
      sample.pegRow,
      verticalScale: scaleY,
    );
  }

  Color get color => switch (risk) {
        'low' => const Color(0xFF00E676),
        'high' => const Color(0xFFFF5252),
        _ => const Color(0xFFFFC107),
      };

  /// Linear time 0..1 mapped onto rows travelled.
  ///
  /// A real ball accelerates under gravity but sheds speed on every peg, so
  /// neither linear (floaty) nor quadratic (rocket) reads right. The exponent
  /// splits the difference: a gentle build that still lands with weight.
  static double rowProgress(double t, int rows) =>
      rows * math.pow(t, 1.42).toDouble();

  /// Where the ball is at [progress], given the peg-position lookup [pegAt].
  ///
  /// [pegAt] takes (row, index) and returns the peg's centre.
  BallFrame frameAt(
    double progress,
    Offset Function(int row, int index) pegAt,
    Offset Function(int slot) slotAt,
    double spacing,
  ) {
    final directions = drop.directions;
    final total = directions.length;
    if (total == 0) {
      return BallFrame(pegAt(0, 0), 1, 0, -1);
    }

    final travelled = rowProgress(progress, total).clamp(0.0, total.toDouble());
    final step = travelled.floor().clamp(0, total - 1);
    final frac = (travelled - step).clamp(0.0, 1.0);

    var index = 0;
    for (var i = 0; i < step; i++) {
      index += directions[i];
    }

    final from = pegAt(step, index);
    final nextIndex = index + directions[step];
    final to =
        step + 1 < total ? pegAt(step + 1, nextIndex) : slotAt(nextIndex);

    // Sideways: quick kick off the peg, easing out — the deflection happens at
    // contact, not spread evenly across the gap.
    final ex = 1 - math.pow(1 - frac, 2.2).toDouble();
    // Vertical: a slight rebound upward off the peg before gravity wins.
    final rebound =
        math.sin(frac * math.pi) * spacing * 0.13 * (1 - frac * 0.55);
    final ey = frac * frac * 0.62 + frac * 0.38;

    final position = Offset(
      from.dx + (to.dx - from.dx) * ex,
      from.dy + (to.dy - from.dy) * ey - rebound,
    );

    // Squash: compressed right at contact, relaxing over the first third of the
    // gap. Sells the impact far more than any amount of extra glow.
    final squash = frac < 0.34 ? 1 - math.cos(frac / 0.34 * math.pi / 2) : 1.0;
    final scaleY = 0.68 + 0.32 * squash;
    final scaleX = 2 - scaleY;

    // Spin follows the direction it was last kicked.
    final spin = (index - total / 2) * 0.55 +
        frac * (directions[step] == 1 ? 1.6 : -1.6);

    return BallFrame(position, scaleX / scaleY, spin, step,
        verticalScale: scaleY);
  }
}

class BallFrame {
  const BallFrame(
    this.position,
    this.aspect,
    this.rotation,
    this.pegRow, {
    this.verticalScale = 1.0,
  });

  final Offset position;

  /// Width/height ratio from the squash.
  final double aspect;
  final double rotation;
  final double verticalScale;

  /// Row of the peg the ball is currently travelling away from.
  final int pegRow;
}

/// A spark thrown out when a ball lands.
class PlinkoParticle {
  PlinkoParticle({
    required this.origin,
    required this.velocity,
    required this.bornAt,
    required this.color,
    required this.size,
    required this.life,
  });

  final Offset origin;
  final Offset velocity;
  final Duration bornAt;
  final Color color;
  final double size;
  final Duration life;

  static const _gravity = 900.0;

  double ageAt(Duration now) =>
      ((now - bornAt).inMicroseconds / life.inMicroseconds).clamp(0.0, 1.0);

  Offset positionAt(Duration now) {
    final t = (now - bornAt).inMicroseconds / 1e6;
    return Offset(
      origin.dx + velocity.dx * t,
      origin.dy + velocity.dy * t + 0.5 * _gravity * t * t,
    );
  }

  /// Spawns a burst sized to the win: a 0.2x landing gets a polite puff, a
  /// jackpot gets a fountain.
  static List<PlinkoParticle> burst({
    required Offset at,
    required Duration now,
    required Color color,
    required double multiplier,
    required math.Random random,
    double scale = 1.0,
  }) {
    final full = multiplier >= 100
        ? 42
        : multiplier >= 10
            ? 26
            : multiplier >= 1
                ? 14
                : 7;
    // Never drop below a handful, or a win on a slow device looks like nothing
    // happened at all.
    final count = math.max(4, (full * scale).round());
    final power = multiplier >= 10 ? 430.0 : 260.0;

    return List.generate(count, (_) {
      // Biased upward: sparks fly out of the slot, not into it.
      final angle = -math.pi / 2 + (random.nextDouble() - 0.5) * 2.2;
      final speed = power * (0.45 + random.nextDouble() * 0.75);
      return PlinkoParticle(
        origin: at,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        bornAt: now,
        color: color,
        size: 1.6 + random.nextDouble() * 2.8,
        life: Duration(milliseconds: 550 + random.nextInt(500)),
      );
    });
  }
}
