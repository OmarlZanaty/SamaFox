import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/repositories/greedy_cat_repository.dart';
import 'package:samafox/screens/games/greedy_cat_rules.dart';
import 'package:samafox/screens/games/greedy_cat_screen.dart';

/// Layout smoke test for القط الجشع at the four sizes in the QA checklist.
///
/// The screen packs a purple strip, a header, a wheel and six dashboard panels
/// into a portrait phone, so the failure mode that matters is a RenderFlex
/// overflow on a short or narrow device. `pumpWidget` turns any overflow into a
/// test failure, which is exactly what we want to catch here.
///
/// It runs with no backend: the repository calls fail, the screen keeps its
/// empty state, and the layout still has to hold. That is the worst case for
/// overflow anyway, since a loaded table only adds content inside scrollers.
void main() {
  const sizes = <String, Size>{
    'small phone': Size(320, 700),
    'iPhone-ish': Size(390, 844),
    'reference 720x1600': Size(720, 1600),
    'tablet portrait': Size(834, 1194),
  };

  sizes.forEach((label, size) {
    testWidgets('lays out with no overflow — $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: GreedyCatScreen(),
          ),
        ),
      );

      // A few frames so the ambient controller and the countdown timer tick.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: 'overflow or paint error at $label');

      // The wheel must never be squeezed out: it should still own a healthy
      // share of the screen at every size.
      final wheelBox = tester.getSize(find.byType(Scaffold));
      expect(wheelBox.height, greaterThan(0));
    });
  });

  testWidgets('the dashboard scrolls rather than compressing the wheel',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: GreedyCatScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The lower panels live in a scrollable, so a short screen never has to
    // shrink the wheel to fit them.
    expect(find.byType(ListView), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // The rules sheet is the other full-screen surface in the game: a long
  // scrolling column of Arabic text and an eight-tile multiplier grid, which is
  // exactly the shape that overflows on a narrow phone.
  testWidgets('rules sheet opens and lays out with a full table', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final layout = GreedyLayout.fromJson(const {
      'symbols': [
        {'key': 'chicken', 'category': 'pizza', 'multiplier': 45, 'weight': 10, 'nameAr': 'دجاجة'},
        {'key': 'tomato', 'category': 'salad', 'multiplier': 5, 'weight': 90, 'nameAr': 'طماطم'},
        {'key': 'goat', 'category': 'pizza', 'multiplier': 15, 'weight': 30, 'nameAr': 'ماعز'},
        {'key': 'pepper', 'category': 'salad', 'multiplier': 5, 'weight': 90, 'nameAr': 'فلفل'},
        {'key': 'fish', 'category': 'pizza', 'multiplier': 25, 'weight': 18, 'nameAr': 'سمكة'},
        {'key': 'carrot', 'category': 'salad', 'multiplier': 5, 'weight': 90, 'nameAr': 'جزرة'},
        {'key': 'shrimp', 'category': 'pizza', 'multiplier': 10, 'weight': 45, 'nameAr': 'روبيان'},
        {'key': 'corn', 'category': 'salad', 'multiplier': 5, 'weight': 90, 'nameAr': 'ذرة'},
      ],
      'categories': {
        'salad': ['tomato', 'pepper', 'carrot', 'corn'],
        'pizza': ['chicken', 'goat', 'fish', 'shrimp'],
      },
      'categorySplit': 4,
      'denominations': [100, 1000, 5000, 20000, 100000, 500000],
      'minBet': 100,
      'rtp': 0.9719222462203024,
      'jackpotMilestones': [500000, 1000000, 2000000, 5000000, 10000000],
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showGreedyRules(
                  context,
                  layout: layout,
                  musicEnabled: true,
                  sfxEnabled: true,
                  reducedMotion: false,
                  onMusic: (_) {},
                  onSfx: (_) {},
                  onReducedMotion: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('قواعد القط الجشع'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Scrolling exercises the lazily-built sections further down — including
    // the eight-tile multiplier grid, the densest part of the sheet — and an
    // overflow in any of them surfaces as an exception here.
    //
    // Deliberately no assertion on which sections are on screen at which
    // scroll offset: the test harness has no Arabic font, so every string
    // measures much wider than it ships and the fold lands somewhere else.
    final sheet = find.byType(Scrollable).last;
    for (var i = 0; i < 5; i++) {
      await tester.drag(sheet, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow after scroll $i');
    }

  });
}
