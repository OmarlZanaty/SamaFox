import 'dart:math';
import 'package:flutter/material.dart';

class DiceChallengeScreen extends StatefulWidget {
  const DiceChallengeScreen({super.key});

  @override
  State<DiceChallengeScreen> createState() => _DiceChallengeScreenState();
}

class _DiceChallengeScreenState extends State<DiceChallengeScreen> {
  static const _bg0 = Color(0xFF0D0620);
  static const _bg1 = Color(0xFF1A0E3E);
  static const _brand = Color(0xFF6B4CE6);
  static const _gold = Color(0xFFFFD36E);

  final _rng = Random();
  int _d1 = 1;
  int _d2 = 1;
  int _score = 0;
  int _rolls = 0;
  int _best = 0;

  // Simple “real game”: 10 rolls, each roll adds (d1+d2).
  // Goal: beat your best.
  void _roll() {
    if (_rolls >= 10) return;
    setState(() {
      _d1 = _rng.nextInt(6) + 1;
      _d2 = _rng.nextInt(6) + 1;
      _score += (_d1 + _d2);
      _rolls++;
      if (_rolls == 10) _best = max(_best, _score);
    });
  }

  void _newRound() {
    setState(() {
      _d1 = 1;
      _d2 = 1;
      _score = 0;
      _rolls = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _rolls >= 10;

    return Scaffold(
      backgroundColor: _bg1,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('نرد التحدي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bg1, _bg0]),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _Pill(label: 'النقاط', value: '$_score', accent: _gold),
                  const SizedBox(width: 10),
                  _Pill(label: 'الرميات', value: '$_rolls/10', accent: _brand),
                  const Spacer(),
                  _Pill(label: 'أفضل نتيجة', value: '$_best', accent: Colors.white),
                ],
              ),

              const SizedBox(height: 22),

              Expanded(
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DieFace(value: _d1),
                      const SizedBox(width: 18),
                      _DieFace(value: _d2),
                    ],
                  ),
                ),
              ),

              Text(
                done ? 'انتهت الجولة! 🎉' : 'اضغط رمي لتجميع أعلى نتيجة خلال 10 رميات',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _Btn(
                      label: done ? 'جولة جديدة' : 'رمي 🎲',
                      onTap: done ? _newRound : _roll,
                      bg: _brand,
                      fg: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Btn(
                      label: 'تصفير',
                      onTap: () {
                        setState(() {
                          _best = 0;
                          _newRound();
                        });
                      },
                      bg: Colors.white.withOpacity(0.12),
                      fg: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 16, spreadRadius: 1)],
      ),
      child: Center(
        child: Text(
          '$value',
          style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.accent});
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap, required this.bg, required this.fg});
  final String label;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Center(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900))),
      ),
    );
  }
}
