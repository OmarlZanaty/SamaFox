import 'package:flutter/material.dart';
import 'yummy_strings.dart';

const yummyArt = 'assets/images/games/yummy/';
const yummySky = Color(0xFF08B9F2);
const yummyDeep = Color(0xFF0753BD);
const yummyGold = Color(0xFFFFD529);
const yummyInk = Color(0xFF10233E);
const yummyEmoji = {
  'strawberry': '🍓',
  'cherry': '🍒',
  'orange': '🍊',
  'lemon': '🍋',
  'watermelon': '🍉',
  'grapes': '🍇',
  'candy': '🍬',
  'diamond': '💎',
  'wild': '⭐',
  'bonus': '🎁',
  'jackpot': '👑',
};

class YummySymbol extends StatelessWidget {
  final String symbol;
  final YummyStrings strings;
  final double size;
  const YummySymbol(
    this.symbol, {
    super.key,
    required this.strings,
    this.size = 56,
  });
  @override
  Widget build(BuildContext context) => Semantics(
        label: strings.text(symbol),
        image: true,
        child: ExcludeSemantics(
          child: Image.asset(
            '$yummyArt$symbol.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Text(
                  yummyEmoji[symbol] ?? '🍓',
                  style: TextStyle(fontSize: size * .7),
                ),
              ),
            ),
          ),
        ),
      );
}

Future<void> yummySheet(
  BuildContext context,
  String title,
  Widget child,
  YummyStrings strings,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF3FAFF),
      builder: (context) => Directionality(
        textDirection: strings.ar ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: yummyInk,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: strings.text('close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          fontSize: 16,
                          color: yummyInk,
                          height: 1.5,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
