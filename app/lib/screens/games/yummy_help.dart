import 'package:flutter/material.dart';
import 'yummy_engine.dart';
import 'yummy_strings.dart';
import 'yummy_symbols.dart';

Widget yummyHelp(YummyStrings strings, Map<String, dynamic> layout) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.text('rules')),
        const SizedBox(height: 16),
        for (final entry in (layout['paytable'] is Map
                ? Map<String, dynamic>.from(layout['paytable'] as Map)
                : yummyPaytable)
            .entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                YummySymbol(entry.key, strings: strings, size: 44),
                const SizedBox(width: 8),
                Expanded(child: Text(strings.text(entry.key))),
                Text(
                  '3: ${entry.value[0]}×  ·  4: ${entry.value[1]}×  ·  5: ${entry.value[2]}×',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        for (final key in [
          'wildRule',
          'bonusHelp',
          'jackpotHelp',
          'stopHelp',
          'caps',
        ])
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(strings.text(key)),
          ),
        const SizedBox(height: 16),
        Text(
          '${strings.text('limits')}: ${layout['minBet']} – ${layout['maxBet']}',
        ),
        Text(
          '${strings.text('roundCap')}: ${layout['maxWinPerRound'] ?? strings.text('unlimited')}',
        ),
        Text(
          '${strings.text('dailyCap')}: ${layout['dailyMaxWinPerUser'] ?? strings.text('unlimited')}',
        ),
        const SizedBox(height: 16),
        Text(strings.footer),
      ],
    );
