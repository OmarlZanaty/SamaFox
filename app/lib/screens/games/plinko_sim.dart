import 'dart:math' as math;
import 'dart:ui';

import '../../repositories/plinko_repository.dart';
import 'plinko_board.dart';

/// Ballistic trajectory for one بلينكو drop.
///
/// The old motion tweened between peg centres, so every ball moved identically
/// and none of them moved like a *ball*. This solves the real thing: each hop is
/// a projectile arc under gravity, with its own flight time, launch speed, spin
/// and the occasional rattle across a peg top.
///
/// It stays exactly as deterministic as before. The server fixed the outcome, so
/// rather than search for launch conditions that happen to land correctly, each
/// arc is *solved* to terminate on the next peg the server chose. Physics
/// governs how it looks; the server governs where it goes. The whole path is
/// computed once at drop time — playback is then a single quadratic per frame,
/// which is cheaper than the tween it replaces.
class PlinkoTrajectory {
  PlinkoTrajectory._(this.arcs, this.totalSeconds, this.gravity);

  final List<PlinkoArc> arcs;
  final double totalSeconds;
  final double gravity;

  /// Cache of the arc used last frame: playback walks forward in time, so the
  /// next lookup is nearly always the same arc or the one after it.
  int _cursor = 0;

  /// Nominal flight time for one peg gap, before per-bounce variation.
  static const _baseHop = 1.0;

  /// How much of the impact speed survives a bounce.
  static const _restitution = 0.55;

  static PlinkoTrajectory build({
    required PlinkoDrop drop,
    required PlinkoLayoutGeometry geometry,
    required math.Random random,
  }) {
    final s = geometry.spacing;
    // Tuned so a 16-row board takes a little over two seconds — fast enough to
    // feel weighty, slow enough to follow.
    final g = 30.0 * s;

    final arcs = <PlinkoArc>[];
    var index = 0;
    var t = 0.0;

    // Release: a short drop onto the first peg from above the apex.
    final apex = geometry.peg(0, 0);
    final entry = Offset(apex.dx, apex.dy - s * 1.6);
    final fallTime = math.sqrt(2 * (s * 1.6) / g);
    arcs.add(PlinkoArc(
      startSeconds: 0,
      duration: fallTime,
      origin: entry,
      velocity: Offset.zero,
      gravity: g,
      pegRow: -1,
      pegIndex: 0,
      spin: 0,
    ));
    t += fallTime;

    for (var row = 0; row < drop.directions.length; row++) {
      final from = geometry.peg(row, index);
      final direction = drop.directions[row];
      final nextIndex = index + direction;
      final to = row + 1 < drop.directions.length
          ? geometry.peg(row + 1, nextIndex)
          : geometry.slot(nextIndex);

      // Flight time varies per bounce: a clean strike throws the ball further
      // and flatter, a glancing one drops it almost straight down. This is what
      // stops sixteen hops from looking like sixteen copies of one hop.
      final energy = 0.82 + random.nextDouble() * 0.42;
      final duration = math.sqrt(2 * s / g) * _baseHop * energy;

      // Solve the launch velocity that puts the ball on the next peg exactly.
      final delta = to - from;
      final vx = delta.dx / duration;
      final vy = (delta.dy - 0.5 * g * duration * duration) / duration;

      // Occasionally the ball catches the top of a peg and stutters before
      // committing — split the hop into a scuff plus the real arc.
      final rattles =
          random.nextDouble() < 0.14 && row < drop.directions.length - 1;
      if (rattles) {
        final scuff = duration * 0.28;
        final mid = Offset(
          from.dx + delta.dx * 0.16,
          from.dy + s * 0.1,
        );
        final mvx = (mid.dx - from.dx) / scuff;
        final mvy = (mid.dy - from.dy - 0.5 * g * scuff * scuff) / scuff;
        arcs.add(PlinkoArc(
          startSeconds: t,
          duration: scuff,
          origin: from,
          velocity: Offset(mvx, mvy),
          gravity: g,
          pegRow: row,
          pegIndex: index,
          spin: direction * 3.0,
        ));
        t += scuff;

        final rest = duration * 0.86;
        final rvx = (to.dx - mid.dx) / rest;
        final rvy = (to.dy - mid.dy - 0.5 * g * rest * rest) / rest;
        arcs.add(PlinkoArc(
          startSeconds: t,
          duration: rest,
          origin: mid,
          velocity: Offset(rvx, rvy),
          gravity: g,
          // Not a fresh contact: the tick already fired for this row.
          pegRow: -1,
          pegIndex: index,
          spin: direction * 5.0,
        ));
        t += rest;
      } else {
        arcs.add(PlinkoArc(
          startSeconds: t,
          duration: duration,
          origin: from,
          velocity: Offset(vx, vy),
          gravity: g,
          pegRow: row,
          pegIndex: index,
          spin: direction * (4.0 + random.nextDouble() * 3.0),
        ));
        t += duration;
      }

      index = nextIndex;
    }

    // Settle: a small dead bounce inside the bin so it does not stop dead.
    final rest = geometry.slot(index);
    final settleTime = math.sqrt(2 * (s * 0.25) / g) * 2;
    arcs.add(PlinkoArc(
      startSeconds: t,
      duration: settleTime,
      origin: rest,
      velocity: Offset(0, -math.sqrt(2 * g * s * 0.25) * _restitution),
      gravity: g,
      pegRow: drop.directions.length,
      pegIndex: index,
      spin: 0,
    ));
    t += settleTime;

    return PlinkoTrajectory._(arcs, t, g);
  }

  /// Position, spin and current arc at [seconds] into the drop.
  TrajectorySample sampleAt(double seconds) {
    if (arcs.isEmpty) {
      return const TrajectorySample(Offset.zero, Offset.zero, 0, -1, 0);
    }

    // Walk from the cached cursor; reset if time moved backwards.
    if (_cursor >= arcs.length || arcs[_cursor].startSeconds > seconds) {
      _cursor = 0;
    }
    while (_cursor + 1 < arcs.length && arcs[_cursor].endSeconds <= seconds) {
      _cursor++;
    }

    final arc = arcs[_cursor];
    final local = (seconds - arc.startSeconds).clamp(0.0, arc.duration);
    return TrajectorySample(
      arc.positionAt(local),
      arc.velocityAt(local),
      arc.spin * local,
      arc.pegRow,
      _cursor.toDouble(),
    );
  }

  /// Index of the arc live at [seconds]; used to detect fresh peg contacts.
  int arcIndexAt(double seconds) => _cursor;
}

/// One projectile hop between two pegs.
class PlinkoArc {
  const PlinkoArc({
    required this.startSeconds,
    required this.duration,
    required this.origin,
    required this.velocity,
    required this.gravity,
    required this.pegRow,
    required this.pegIndex,
    required this.spin,
  });

  final double startSeconds, duration, gravity, spin;
  final Offset origin, velocity;

  /// Row of the peg this arc launches from, or -1 when it is not a fresh
  /// contact (the release drop and the second half of a rattle).
  final int pegRow;
  final int pegIndex;

  double get endSeconds => startSeconds + duration;

  Offset positionAt(double local) => Offset(
        origin.dx + velocity.dx * local,
        origin.dy + velocity.dy * local + 0.5 * gravity * local * local,
      );

  Offset velocityAt(double local) =>
      Offset(velocity.dx, velocity.dy + gravity * local);
}

class TrajectorySample {
  const TrajectorySample(
    this.position,
    this.velocity,
    this.rotation,
    this.pegRow,
    this.arcIndex,
  );

  final Offset position;
  final Offset velocity;
  final double rotation;
  final int pegRow;
  final double arcIndex;
}
