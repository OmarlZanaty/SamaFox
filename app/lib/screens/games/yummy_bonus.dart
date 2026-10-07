import 'package:flutter/material.dart';
import 'yummy_engine.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

class YummyBonus extends StatefulWidget {
  final YummyRound round;
  final YummyStrings strings;
  const YummyBonus({super.key, required this.round, required this.strings});
  @override
  State<YummyBonus> createState() => _YummyBonusState();
}

class _YummyBonusState extends State<YummyBonus> {
  int? _picked;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.strings.text(_picked == null ? 'pick' : 'bonusAward'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Semantics(
                  label: '${widget.strings.text('pick')} ${index + 1}',
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _picked == null
                        ? () => setState(() => _picked = index)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        '$yummyArt${_picked == index ? 'bonus_open' : 'bonus_chest'}.png',
                        height: 100,
                        errorBuilder: (_, __, ___) => Text(
                          _picked == index ? '✨' : '🎁',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 60,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_picked != null)
            Text(
              '${widget.round.bonusMultiplier}×  ·  ${widget.round.bonusPrize}',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: yummyDeep,
              ),
            ),
          if (widget.round.capped) Text(widget.strings.text('capped')),
          const SizedBox(height: 16),
          Text(widget.strings.text('bonusRule'), textAlign: TextAlign.center),
        ],
      );
}
