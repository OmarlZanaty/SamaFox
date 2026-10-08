import 'package:flutter/material.dart';

const fruitJackpotEmoji = {
  'lemon': '🍋',
  'raspberry': '🫐',
  'kiwi': '🥝',
  'cherry': '🍒',
  'plum': '🟣',
  'watermelon': '🍉',
  'banana': '🍌',
  'strawberry': '🍓',
  'multiplier': '×2',
};
Widget fruitJackpotArt(
  String name, {
  double? width,
  double? height,
  String? label,
}) => Image.asset(
  'assets/images/games/fruit_jackpot/$name.png',
  width: width,
  height: height,
  fit: BoxFit.contain,
  semanticLabel: label ?? name,
  errorBuilder: (_, __, ___) => Center(
    child: Text(
      fruitJackpotEmoji[name] ?? (name == 'logo_jackpot' ? 'JACKPOT' : '✦'),
      style: TextStyle(
        fontSize: name == 'logo_jackpot' ? 42 : 32,
        color: const Color(0xffffd52b),
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
);
