import 'package:flutter/material.dart';
import 'fruit_jackpot_symbols.dart';

class FruitJackpotBonus extends StatefulWidget {
  final int multiplier;
  final bool arabic;
  const FruitJackpotBonus({
    super.key,
    required this.multiplier,
    required this.arabic,
  });
  @override
  State<FruitJackpotBonus> createState() => _FruitJackpotBonusState();
}

class _FruitJackpotBonusState extends State<FruitJackpotBonus> {
  int? picked;
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xff35134e),
    title: Text(widget.arabic ? 'جولة المكافأة' : 'BONUS ROUND'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.arabic
              ? 'اختر بطاقة لكشف مكافأتك المحسوبة'
              : 'Choose a card to reveal your awarded bonus',
        ),
        Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Semantics(
                label: '${widget.arabic ? 'بطاقة' : 'Card'} ${i + 1}',
                button: true,
                child: InkWell(
                  onTap: picked == null
                      ? () => setState(() => picked = i)
                      : null,
                  child: SizedBox(
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        fruitJackpotArt(
                          picked == i ? 'bonus_card_front' : 'bonus_card_back',
                        ),
                        if (picked == i)
                          Text(
                            '×${widget.multiplier}',
                            style: const TextStyle(
                              fontSize: 32,
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.arabic ? 'إغلاق' : 'Close'),
      ),
    ],
  );
}
