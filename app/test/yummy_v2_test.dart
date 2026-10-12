import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/screens/games/yummy_engine.dart';
import 'package:samafox/screens/games/yummy_social.dart';
import 'yummy_engine_test.dart' show yummyFixture;

/// Math v2 on the client: parsing tumbles and free spins (tolerant of v1
/// history), the collapse mirror, anticipation and autoplay bookkeeping.

List<String> board(String fill) => List<String>.filled(15, fill);

Map<String, dynamic> tumble(
  List<String> grid,
  int prize,
  List<int> removed, {
  int multiplier = 1,
  List<Map<String, dynamic>> wins = const [],
}) =>
    {
      'grid': grid,
      'wins': wins,
      'multiplier': multiplier,
      'prize': prize,
      'removed': removed,
    };

Map<String, dynamic> v2Fixture() {
  final fixture = yummyFixture(prize: 5400, balance: 54500);
  final spin = fixture['spin'] as Map<String, dynamic>;
  final first = List<String>.from(spin['grid'] as List);
  final second = [...first]..[5] = 'lemon';
  spin['mathVersion'] = 2;
  spin['basePrize'] = 600;
  spin['tumbles'] = [
    tumble(first, 200, [5, 6, 7], wins: List.from(spin['wins'] as List)),
    tumble(
      second,
      400,
      [5, 6, 7],
      multiplier: 2,
      wins: [
        {
          'line': 0,
          'symbol': 'strawberry',
          'count': 3,
          'cells': [5, 6, 7],
          'amount': 200,
        },
      ],
    ),
    tumble(second, 0, [], multiplier: 3),
  ];
  final landed = board('cherry')..[2] = 'wild';
  final expanded = [...landed]
    ..[7] = 'wild'
    ..[12] = 'wild';
  spin['freeSpins'] = {
    'count': 8,
    'multiplier': 2,
    'trigger': 3,
    'prize': 4800,
    'spins': [
      {
        'landed': landed,
        'expandedReels': [2],
        'tumbles': [tumble(expanded, 4800, [])],
        'prize': 4800,
      },
      for (var i = 1; i < 8; i++)
        {
          'landed': board('lemon'),
          'expandedReels': [],
          'tumbles': [tumble(board('lemon'), 0, [])],
          'prize': 0,
        },
    ],
  };
  spin['bonusTriggered'] = true;
  return fixture;
}

void main() {
  test('parses tumbles, multipliers and free spins from a v2 round', () {
    final round = YummyRound.fromJson(v2Fixture());
    expect(round.mathVersion, 2);
    expect(round.tumbles, hasLength(3));
    expect(round.tumbles.map((t) => t.multiplier), [1, 2, 3]);
    expect(round.tumbleChain, 2);
    expect(round.tumbles.first.removed, [5, 6, 7]);
    expect(round.finalGrid[5], 'lemon');
    expect(round.basePrize, 600);
    expect(round.baseShown, 600);
    final free = round.freeSpins!;
    expect(free.count, 8);
    expect(free.multiplier, 2);
    expect(free.spins, hasLength(8));
    expect(free.spins.first.expandedReels, [2]);
    expect(free.spins.first.landed[7], 'cherry');
    expect(free.spins.first.tumbles.first.grid[7], 'wild');
    expect(round.freeSpinsShown, 4800);
    expect(round.allWins, hasLength(2));
  });

  test('v1 rounds still parse: one synthesised step, no free spins', () {
    final round = YummyRound.fromJson(yummyFixture());
    expect(round.mathVersion, 1);
    expect(round.tumbles, hasLength(1));
    expect(round.tumbles.single.grid, round.grid);
    expect(round.tumbles.single.prize, 200);
    expect(round.freeSpins, isNull);
    expect(round.freeSpinsShown, 0);
  });

  test('a capped round never shows more than it paid', () {
    final fixture = v2Fixture();
    (fixture['spin'] as Map)['totalPrize'] = 300;
    (fixture['spin'] as Map)['capped'] = true;
    final round = YummyRound.fromJson(fixture);
    expect(round.baseShown, 300);
    expect(round.freeSpinsShown, 0);
  });

  test('malformed tumbles and free spins are rejected or ignored safely', () {
    final bad = v2Fixture();
    ((bad['spin'] as Map)['tumbles'] as List)[0]['grid'] = ['nope'];
    expect(() => YummyRound.fromJson(bad), throwsFormatException);
    final odd = v2Fixture();
    (odd['spin'] as Map)['freeSpins'] = 'garbage';
    expect(YummyRound.fromJson(odd).freeSpins, isNull);
    final noLanded = v2Fixture();
    final spins =
        ((noLanded['spin'] as Map)['freeSpins'] as Map)['spins'] as List;
    (spins.first as Map).remove('landed');
    final spin = YummyRound.fromJson(noLanded).freeSpins!.spins.first;
    // Without the pre-expansion board it lands on the expanded one directly.
    expect(spin.expandedReels, isEmpty);
    expect(spin.landed[7], 'wild');
  });

  test('fall sources mirror the server collapse', () {
    // Middle row popped: the top row falls one, new symbols above.
    final sources = yummyFallSources([5, 6, 7, 8, 9]);
    for (var reel = 0; reel < 5; reel++) {
      expect(sources[reel], -1);
      expect(sources[5 + reel], 0);
      expect(sources[10 + reel], 2);
    }
    // A whole reel popped: three new symbols, nothing falls.
    final column = yummyFallSources([0, 5, 10]);
    expect([column[0], column[5], column[10]], [-3, -2, -1]);
    expect(column[1], 0);
  });

  test('anticipation needs two BONUS, or crowns on every landed reel', () {
    final grid = board('cherry');
    expect(yummyAnticipates(grid, 2), isFalse);
    grid[0] = 'bonus';
    grid[6] = 'bonus';
    expect(yummyAnticipates(grid, 1), isFalse);
    expect(yummyAnticipates(grid, 2), isTrue);
    expect(yummyAnticipates(grid, 5), isFalse);
    final crowns = board('lemon')
      ..[5] = 'jackpot'
      ..[1] = 'jackpot';
    expect(yummyAnticipates(crowns, 2), isTrue);
    expect(yummyAnticipates(crowns, 3), isFalse);
  });

  group('autoplay stops', () {
    YummyAutoplay make({
      int spins = 10,
      int? loss,
      int? win,
      bool free = true,
    }) =>
        YummyAutoplay(
          YummyAutoSettings(
            spins: spins,
            lossLimitX: loss,
            winLimitX: win,
            stopOnFreeSpins: free,
          ),
          10000,
        );
    test('after the chosen number of spins', () {
      final auto = make(spins: 3);
      expect(
        auto.next(balance: 9900, totalBet: 100, prize: 0, freeSpins: false),
        isTrue,
      );
      expect(
        auto.next(balance: 9800, totalBet: 100, prize: 0, freeSpins: false),
        isTrue,
      );
      expect(
        auto.next(balance: 9700, totalBet: 100, prize: 0, freeSpins: false),
        isFalse,
      );
      expect(auto.stoppedBy, 'done');
    });
    test('on the loss limit', () {
      final auto = make(loss: 2);
      expect(
        auto.next(balance: 9900, totalBet: 100, prize: 0, freeSpins: false),
        isTrue,
      );
      expect(
        auto.next(balance: 9800, totalBet: 100, prize: 0, freeSpins: false),
        isFalse,
      );
      expect(auto.stoppedBy, 'loss');
    });
    test('on a single big win', () {
      final auto = make(win: 10);
      expect(
        auto.next(balance: 10900, totalBet: 100, prize: 999, freeSpins: false),
        isTrue,
      );
      expect(
        auto.next(balance: 11900, totalBet: 100, prize: 1000, freeSpins: false),
        isFalse,
      );
      expect(auto.stoppedBy, 'win');
    });
    test('on free spins only when asked', () {
      final stop = make();
      expect(
        stop.next(balance: 9900, totalBet: 100, prize: 0, freeSpins: true),
        isFalse,
      );
      expect(stop.stoppedBy, 'freeSpins');
      final keep = make(free: false);
      expect(
        keep.next(balance: 9900, totalBet: 100, prize: 0, freeSpins: true),
        isTrue,
      );
    });
    test('when coins run out', () {
      final auto = make();
      expect(
        auto.next(balance: 50, totalBet: 100, prize: 0, freeSpins: false),
        isFalse,
      );
      expect(auto.stoppedBy, 'balance');
    });
  });

  test('win feed parses broadcasts and ignores junk', () {
    final feed = YummyWinFeed.instance..wins.clear();
    feed.add({
      'game': 'yummy',
      'userId': 3,
      'name': 'Mona',
      'prize': 52000,
      'x': 57.8,
      'tier': 'big',
    });
    feed.add('junk');
    feed.add({'name': 'no prize'});
    expect(feed.wins, hasLength(1));
    expect(feed.wins.first.prize, 52000);
    feed.seed([
      {'prize': 1, 'name': 'ignored because the socket already filled it'},
    ]);
    expect(feed.wins, hasLength(1));
    feed.wins.clear();
  });
}
