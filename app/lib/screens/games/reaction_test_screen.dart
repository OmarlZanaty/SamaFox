import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class ReactionTestScreen extends StatefulWidget {
  const ReactionTestScreen({super.key});

  @override
  State<ReactionTestScreen> createState() => _ReactionTestScreenState();
}

class _ReactionTestScreenState extends State<ReactionTestScreen> {
  static const _bg0 = Color(0xFF0D0620);
  static const _bg1 = Color(0xFF1A0E3E);
  static const _brand = Color(0xFF6B4CE6);
  static const _good = Color(0xFF4CAF50);
  static const _bad = Color(0xFFFF2D55);

  final _rng = Random();
  Timer? _timer;

  bool _waiting = false;
  bool _go = false;
  DateTime? _startAt;
  int? _lastMs;
  int? _bestMs;
  String _hint = 'اضغط "ابدأ" ثم انتظر كلمة (اضغط الآن)';

  void _start() {
    _timer?.cancel();
    setState(() {
      _waiting = true;
      _go = false;
      _startAt = null;
      _hint = 'انتظر... لا تضغط الآن';
    });

    final delay = 800 + _rng.nextInt(2200); // 0.8s - 3.0s
    _timer = Timer(Duration(milliseconds: delay), () {
      setState(() {
        _go = true;
        _startAt = DateTime.now();
        _hint = 'اضغط الآن!';
      });
    });
  }

  void _tap() {
    if (!_waiting) return;

    // False start
    if (!_go) {
      _timer?.cancel();
      setState(() {
        _waiting = false;
        _go = false;
        _hint = 'انطلقت بدري 😅 حاول تاني';
        _lastMs = null;
      });
      return;
    }

    final ms = DateTime.now().difference(_startAt!).inMilliseconds;
    setState(() {
      _waiting = false;
      _go = false;
      _lastMs = ms;
      _bestMs = (_bestMs == null) ? ms : (_bestMs! < ms ? _bestMs : ms);
      _hint = 'نتيجتك: ${ms}ms';
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = !_waiting
        ? _brand
        : (_go ? _good : _bad);

    return Scaffold(
      backgroundColor: _bg1,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('اختبار السرعة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
                  _Pill(label: 'آخر نتيجة', value: _lastMs == null ? '—' : '${_lastMs}ms'),
                  const SizedBox(width: 10),
                  _Pill(label: 'أفضل نتيجة', value: _bestMs == null ? '—' : '${_bestMs}ms'),
                ],
              ),

              const SizedBox(height: 20),

              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: _tap,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color: color.withOpacity(0.20),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Center(
                      child: Text(
                        _hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

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
                      label: 'تصفير',
                      onTap: () => setState(() {
                        _timer?.cancel();
                        _waiting = false;
                        _go = false;
                        _lastMs = null;
                        _bestMs = null;
                        _hint = 'اضغط "ابدأ" ثم انتظر كلمة (اضغط الآن)';
                      }),
                      bg: Colors.white.withOpacity(0.12),
                      fg: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});
  final String label;
  final String value;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.70), fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
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
