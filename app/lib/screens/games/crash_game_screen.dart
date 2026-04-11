import 'dart:math';
import 'package:flutter/material.dart';

class CrashGameScreen extends StatefulWidget {
  const CrashGameScreen({super.key});

  @override
  State<CrashGameScreen> createState() => _CrashGameScreenState();
}

class _CrashGameScreenState extends State<CrashGameScreen> {
  final Random _random = Random();
  int _balance = 1000;
  int _bet = 100;
  bool _roundRunning = false;
  bool _cashedOut = false;
  double _multiplier = 1.00;
  double _crashAt = 1.0;
  String _status = 'ابدأ الجولة ثم اسحب أرباحك قبل الانهيار';

  void _startRound() {
    if (_roundRunning || _bet > _balance) {
      setState(() => _status = _bet > _balance ? 'رصيد غير كافٍ' : _status);
      return;
    }

    setState(() {
      _roundRunning = true;
      _cashedOut = false;
      _multiplier = 1.00;
      _crashAt = 1.2 + (_random.nextDouble() * 4.8);
      _balance -= _bet;
      _status = 'الجولة بدأت! اسحب قبل $_crashAt x';
    });

    _tickRound();
  }

  void _tickRound() {
    if (!_roundRunning) return;

    Future.delayed(const Duration(milliseconds: 140), () {
      if (!mounted || !_roundRunning) return;

      final next = _multiplier + 0.06 + (_multiplier * 0.02);
      if (next >= _crashAt) {
        setState(() {
          _multiplier = _crashAt;
          _roundRunning = false;
          if (!_cashedOut) {
            _status = '💥 انهارت! خسرت الرهان';
          }
        });
        return;
      }

      setState(() => _multiplier = next);
      _tickRound();
    });
  }

  void _cashOut() {
    if (!_roundRunning || _cashedOut) return;
    final int win = (_bet * _multiplier).floor();
    setState(() {
      _balance += win;
      _cashedOut = true;
      _roundRunning = false;
      _status = '✅ سحبت أرباحك: $win';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كراش 🚀')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _TopInfo(balance: _balance, status: _status),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [Color(0xFF0f2027), Color(0xFF203a43)]),
                  ),
                  child: Center(
                    child: Text('${_multiplier.toStringAsFixed(2)}x',
                        style: TextStyle(
                          color: _roundRunning ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('الرهان'),
                  Expanded(
                    child: Slider(
                      min: 50,
                      max: 500,
                      divisions: 18,
                      value: _bet.toDouble(),
                      label: '$_bet',
                      onChanged: _roundRunning ? null : (v) => setState(() => _bet = v.round()),
                    ),
                  ),
                  Text('$_bet'),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _roundRunning ? null : _startRound,
                      child: const Text('بدء الجولة'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _roundRunning ? _cashOut : null,
                      child: const Text('سحب الآن'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _TopInfo extends StatelessWidget {
  final int balance;
  final String status;
  const _TopInfo({required this.balance, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('الرصيد: $balance', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(status),
      ]),
    );
  }
}
