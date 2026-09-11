import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/repositories/olympus_repository.dart';
import 'package:samafox/screens/games/olympus_symbols.dart';

/// Contract tests for بوابات أوليمبوس between the server and this client.
///
/// The fixture is real output from the shipped spin math — regenerate it with
/// `npm run dump:olympus` in backend/ — so these tests fail loudly if the
/// payload shape drifts, if a new symbol id appears that the client cannot
/// draw, or if the frame stream stops adding up to the totals the client shows.
///
/// The animation timing is not tested here; what is tested is that every number
/// the player is shown can actually be derived from the frames the server sent.
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final file = File('test/olympus_spin_samples.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Run `npm run dump:olympus` in backend/ to regenerate the fixture',
    );
    fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  OlympusSpin spinOf(String name) => OlympusSpin.fromJson(
        Map<String, dynamic>.from(
          (fixture[name] as Map)['spin'] as Map,
        ),
      );

  final cases = ['plain_loss', 'three_mults', 'bonus_retrigger', 'epic_win'];

  group('parses every sample', () {
    for (final name in cases) {
      test(name, () {
        final spin = spinOf(name);
        expect(spin.bet, 20);
        expect(spin.initialGrid, hasLength(30));
        expect(spin.frames, isNotEmpty);

        for (final frame in spin.frames) {
          expect(frame.grid, hasLength(30), reason: 'every frame is a full board');
          expect(frame.phase, anyOf('base', 'free'));

          // Anything the server can put on the board, the client must be able
          // to draw. A new symbol id shipping server-first would otherwise show
          // up as a silently blank cell.
          for (final id in frame.grid) {
            expect(
              kOlympusSymbols.containsKey(id),
              isTrue,
              reason: 'no visual defined for symbol "$id"',
            );
          }

          for (final cell in frame.multCells) {
            expect(cell.index, inInclusiveRange(0, 29));
            expect(cell.value, greaterThan(0));
            expect(
              frame.grid[cell.index],
              'MULT',
              reason: 'a multiplier cell must actually hold a MULT symbol',
            );
          }

          // Multipliers are inert scenery until a cascade ends: they never pay
          // on their own and never count toward a match, so they must never be
          // listed as winning cells.
          for (final i in frame.winningCells) {
            expect(frame.grid[i], isNot('MULT'));
            expect(frame.grid[i], isNot('SCATTER'));
          }
        }
      });
    }
  });

  test('every win group is at least the minimum match', () {
    for (final name in cases) {
      for (final frame in spinOf(name).frames) {
        for (final win in frame.wins) {
          expect(
            win.count,
            greaterThanOrEqualTo(8),
            reason: '$name paid a group of ${win.count}',
          );
          // Pay-anywhere: the winning cells are exactly the cells holding that
          // symbol, so the count has to match what is on the board.
          final onBoard = frame.grid.where((s) => s == win.symbol).length;
          expect(onBoard, win.count, reason: '$name: ${win.symbol} count');
        }
      }
    }
  });

  test('frame totals sum to the round total', () {
    for (final name in cases) {
      final spin = spinOf(name);
      final summed = spin.frames
          .where((f) => f.sequenceTotal != null)
          .fold<int>(0, (a, f) => a + f.sequenceTotal!);
      expect(
        summed,
        spin.uncappedTotal,
        reason: '$name: the frames the client replays must add up to the '
            'uncapped total, or the running counter will disagree with the payout',
      );
      expect(spin.grandTotal, lessThanOrEqualTo(spin.uncappedTotal));
      expect(spin.capped, spin.uncappedTotal > spin.grandTotal);
    }
  });

  test('a losing round pays nothing and shows no celebration', () {
    final spin = spinOf('plain_loss');
    expect(spin.grandTotal, 0);
    expect(spin.tier, isNull);
    expect(spin.freeTriggered, isFalse);
  });

  test('multipliers add rather than multiply', () {
    final spin = spinOf('three_mults');
    final last = spin.frames.lastWhere((f) => f.phase == 'base' && f.sequenceTotal != null);

    // The rule the help sheet states in words, asserted on real output: the
    // sequence multiplier is the *sum* of the orbs left on the board.
    expect(last.multCells.length, greaterThanOrEqualTo(2));
    expect(last.sequenceMultiplier, last.multiplierTotal);

    final product = last.multCells.fold<int>(1, (a, m) => a * m.value);
    expect(
      last.sequenceMultiplier,
      isNot(product),
      reason: 'summing and multiplying must not be confusable in this fixture',
    );

    // And the payout is the raw win scaled by that sum.
    expect(last.sequenceTotal, (last.sequenceWin! * last.sequenceMultiplier!).floor());
  });

  test('the bonus awards spins, retriggers, and a meter that never falls', () {
    final spin = spinOf('bonus_retrigger');
    expect(spin.freeTriggered, isTrue);
    expect(spin.scattersInitial, greaterThanOrEqualTo(4));
    expect(spin.freeRetriggers, greaterThan(0));

    // 15 base spins plus 5 per retrigger.
    expect(spin.freeSpins, 15 + spin.freeRetriggers * 5);

    final free = spin.frames.where((f) => f.phase == 'free').toList();
    expect(free, isNotEmpty);

    // Each free spin is numbered, and the numbering is contiguous from 1.
    final numbered = free.where((f) => f.spinNumber != null).map((f) => f.spinNumber!).toList();
    expect(numbered, List.generate(spin.freeSpins, (i) => i + 1));

    // The meter is the whole feature: it may grow but must never reset while
    // the bonus runs, which is exactly what the HUD promises the player.
    var meter = 0;
    for (final f in free.where((f) => f.freeMultiplierAfter != null)) {
      expect(f.freeMultiplierAfter!, greaterThanOrEqualTo(meter));
      meter = f.freeMultiplierAfter!;
    }
    expect(spin.freeMultiplier, meter);
  });

  test('a big win carries a tier the client has a label and sound for', () {
    final spin = spinOf('epic_win');
    expect(spin.tier, 'EPIC_WIN');
    expect(spin.grandTotal, greaterThanOrEqualTo(spin.bet * 100));
  });

  test('the QA seed the debug sheet uses matches the fixture', () {
    // The scenario sheet in olympus_screen.dart hardcodes this pair. If the
    // dump script's seed ever changes, this catches the drift rather than
    // leaving the sheet quietly replaying different rounds than the sim named.
    final meta = Map<String, dynamic>.from(fixture['_meta'] as Map);
    expect(
      meta['serverSeed'],
      'olympus-qa-server-seed000000000000000000000000000000000000000000',
    );
    expect(meta['clientSeed'], 'qa');
    expect(meta['bet'], 20);
  });
}
