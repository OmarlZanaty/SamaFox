import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/repositories/plinko_repository.dart';
import 'package:samafox/screens/games/plinko_board.dart';
import 'package:samafox/screens/games/plinko_sim.dart';

/// The trajectory is presentation, but it must never contradict the server: a
/// ball has to come to rest in the slot the server paid out on. These tests
/// hammer that invariant across every board size and every path shape.
void main() {
  PlinkoLayoutGeometry geometryFor(int rows) {
    const size = Size(400, 700);
    final slotHeight = math.min(34.0, size.height * 0.09);
    final boardHeight = size.height - slotHeight - 10;
    final spacing = math.min(size.width / (rows + 2), boardHeight / (rows + 1));
    return PlinkoLayoutGeometry(
      rows: rows,
      slotCount: rows + 1,
      spacing: spacing,
      centerX: size.width / 2,
      topY: (boardHeight - spacing * rows) / 2 + spacing * 0.5,
      slotY: size.height - slotHeight,
      slotHeight: slotHeight,
      size: size,
    );
  }

  PlinkoDrop dropWith(List<int> directions) => PlinkoDrop(
        nonce: 0,
        risk: 'medium',
        rows: directions.length,
        slot: directions.fold(0, (a, b) => a + b),
        multiplier: 1,
        bet: 100,
        payout: 100,
        directions: directions,
      );

  test('every path lands in the slot the server chose', () {
    final random = math.Random(20260729);
    var checked = 0;

    for (var rows = 8; rows <= 16; rows++) {
      final geometry = geometryFor(rows);

      for (var trial = 0; trial < 220; trial++) {
        final directions =
            List<int>.generate(rows, (_) => random.nextBool() ? 1 : 0);
        final drop = dropWith(directions);
        final trajectory = PlinkoTrajectory.build(
          drop: drop,
          geometry: geometry,
          random: random,
        );

        final end = trajectory.sampleAt(trajectory.totalSeconds).position;
        final expected = geometry.slot(drop.slot);

        // Within a fraction of a peg gap of the slot centre.
        expect(
          (end.dx - expected.dx).abs(),
          lessThan(geometry.spacing * 0.5),
          reason: 'rows=$rows slot=${drop.slot} landed at ${end.dx}, '
              'expected ${expected.dx}',
        );
        checked++;
      }
    }

    expect(checked, greaterThan(1900));
  });

  test('extreme paths — hard left and hard right — still land correctly', () {
    final random = math.Random(7);
    for (var rows = 8; rows <= 16; rows++) {
      final geometry = geometryFor(rows);

      for (final directions in [
        List<int>.filled(rows, 0), // every bounce left
        List<int>.filled(rows, 1), // every bounce right
      ]) {
        final drop = dropWith(directions);
        final trajectory = PlinkoTrajectory.build(
          drop: drop,
          geometry: geometry,
          random: random,
        );
        final end = trajectory.sampleAt(trajectory.totalSeconds).position;
        final expected = geometry.slot(drop.slot);
        expect((end.dx - expected.dx).abs(), lessThan(geometry.spacing * 0.5),
            reason: 'rows=$rows edge slot ${drop.slot}');
      }
    }
  });

  test('the ball only ever moves downward between pegs', () {
    final random = math.Random(99);
    final geometry = geometryFor(16);
    final drop =
        dropWith(List<int>.generate(16, (_) => random.nextBool() ? 1 : 0));
    final trajectory =
        PlinkoTrajectory.build(drop: drop, geometry: geometry, random: random);

    // Sampled densely: a solved arc that overshoots upward would read as the
    // ball floating back up the board.
    var previousY = double.negativeInfinity;
    var rises = 0;
    for (var t = 0.0; t <= trajectory.totalSeconds; t += 1 / 120) {
      final y = trajectory.sampleAt(t).position.dy;
      if (y < previousY - geometry.spacing * 0.35) rises++;
      previousY = y;
    }
    expect(rises, 0, reason: 'ball rose more than a third of a peg gap');
  });

  test('duration scales with board size and stays playable', () {
    final random = math.Random(5);
    for (var rows = 8; rows <= 16; rows++) {
      final drop = dropWith(List<int>.filled(rows, 1));
      final trajectory = PlinkoTrajectory.build(
        drop: drop,
        geometry: geometryFor(rows),
        random: random,
      );
      expect(trajectory.totalSeconds, greaterThan(0.6));
      expect(trajectory.totalSeconds, lessThan(6.0));
    }
  });
}
