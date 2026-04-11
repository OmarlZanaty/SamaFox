import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class MathChallengeScreen extends StatefulWidget {
  const MathChallengeScreen({super.key});

  @override
  State<MathChallengeScreen> createState() => _MathChallengeScreenState();
}

class _MathChallengeScreenState extends State<MathChallengeScreen> {
  static const _bg0 = Color(0xFF0D0620);
  static const _bg1 = Color(0xFF1A0E3E);
  static const _brand = Color(0xFF6B4CE6);
  static const _gold = Color(0xFFFFD36E);
  static const _good = Color(0xFF4CAF50);
  static const _bad = Color(0xFFFF2D55);

  final _rng = Random();
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _timer;
  int _seconds = 30;
  int _score = 0;

  String _qText = '';
  int _answer = 0;
  String _feedback = 'ابدأ التحدي 👇';
  Color _feedbackColor = Colors.white;

  void _newQuestion() {
    final a = _rng.nextInt(20) + 1;
    final b = _rng.nextInt(20) + 1;

    // Keep it simple & fast: +, -, *
    final op = _rng.nextInt(3);
    int ans;
    String text;

    if (op == 0) {
      ans = a + b;
      text = '$a + $b = ?';
    } else if (op == 1) {
      final big = max(a, b);
      final small = min(a, b);
      ans = big - small;
      text = '$big - $small = ?';
    } else {
      final m1 = _rng.nextInt(9) + 2;
      final m2 = _rng.nextInt(9) + 2;
      ans = m1 * m2;
      text = '$m1 × $m2 = ?';
    }

    setState(() {
      _qText = text;
      _answer = ans;
      _controller.clear();
      _feedback = 'اكتب الإجابة ثم اضغط تحقق';
      _feedbackColor = Colors.white.withOpacity(0.85);
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _focus.requestFocus();
    });
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _seconds = 30;
      _score = 0;
      _feedback = 'ابدأ!';
      _feedbackColor = Colors.white;
    });

    _newQuestion();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds--);

      if (_seconds <= 0) {
        t.cancel();
        setState(() {
          _feedback = 'انتهى الوقت! نتيجتك: $_score';
          _feedbackColor = _gold;
        });
        _focus.unfocus();
      }
    });
  }

  void _check() {
    if (_seconds <= 0 || _qText.isEmpty) return;

    final txt = _controller.text.trim();
    final val = int.tryParse(txt);

    if (val == null) {
      setState(() {
        _feedback = 'اكتب رقم صحيح';
        _feedbackColor = _bad;
      });
      return;
    }

    if (val == _answer) {
      setState(() {
        _score++;
        _feedback = 'صح ✅ +1';
        _feedbackColor = _good;
      });
      _newQuestion();
    } else {
      setState(() {
        _feedback = 'غلط ❌ حاول تاني';
        _feedbackColor = _bad;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _seconds > 0 && _qText.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg1,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('تحدي الحساب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
                  _Pill(label: 'الوقت', value: '$_seconds', accent: _gold),
                  const SizedBox(width: 10),
                  _Pill(label: 'النقاط', value: '$_score', accent: _brand),
                ],
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.14)),
                ),
                child: Column(
                  children: [
                    Text(
                      _qText.isEmpty ? 'اضغط "ابدأ" لبدء التحدي' : _qText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        hintText: 'الإجابة',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _check(),
                    ),
                    const SizedBox(height: 12),
                    Text(_feedback, style: TextStyle(color: _feedbackColor, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),

              const Spacer(),

              Row(
                children: [
                  Expanded(
                    child: _Btn(
                      label: 'ابدأ',
                      onTap: _start,
                      bg: _brand,
                      fg: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Btn(
                      label: 'تحقق',
                      onTap: running ? _check : () {},
                      bg: Colors.white.withOpacity(running ? 0.12 : 0.06),
                      fg: Colors.white.withOpacity(running ? 1.0 : 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('$label: ', style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w800)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
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
