import 'dart:math';
import 'package:flutter/material.dart';

class LionTigerScreen extends StatefulWidget {
  const LionTigerScreen({super.key});

  @override
  State<LionTigerScreen> createState() => _LionTigerScreenState();
}

class _LionTigerScreenState extends State<LionTigerScreen> {
  final Random _random = Random();
  int _balance = 1000;
  int _bet = 100;
  String _selected = 'lion';
  String _result = 'قم بالمراهنة: الأسد أو النمر أو تعادل';
  int _lionPower = 50;
  int _tigerPower = 50;

  void _fight() {
    if (_bet > _balance) {
      setState(() => _result = 'رصيدك لا يكفي');
      return;
    }

    final lionRoll = 30 + _random.nextInt(71);
    final tigerRoll = 30 + _random.nextInt(71);
    final bool draw = (lionRoll - tigerRoll).abs() <= 4;

    int multiplier = 0;
    String winner;
    if (draw) {
      winner = 'draw';
      if (_selected == 'draw') multiplier = 8;
    } else if (lionRoll > tigerRoll) {
      winner = 'lion';
      if (_selected == 'lion') multiplier = 2;
    } else {
      winner = 'tiger';
      if (_selected == 'tiger') multiplier = 2;
    }

    setState(() {
      _lionPower = lionRoll;
      _tigerPower = tigerRoll;
      _balance -= _bet;
      if (multiplier > 0) {
        final win = _bet * multiplier;
        _balance += win;
        _result = winner == 'draw'
            ? '⚖️ تعادل! ربحت $win'
            : winner == 'lion'
                ? '🦁 الأسد فاز! ربحت $win'
                : '🐯 النمر فاز! ربحت $win';
      } else {
        _result = winner == 'draw'
            ? '⚖️ تعادل! خسرت الرهان'
            : winner == 'lion'
                ? '🦁 الأسد فاز، حظ أوفر'
                : '🐯 النمر فاز، حظ أوفر';
      }
    });
  }

  Widget _choice(String id, String label) {
    final selected = _selected == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selected = id),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.amber.shade200 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.orange : Colors.grey.shade300),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأسد vs النمر')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text('الرصيد: $_balance', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _powerCard('🦁 الأسد', _lionPower, Colors.deepOrange)),
                  const SizedBox(width: 8),
                  Expanded(child: _powerCard('🐯 النمر', _tigerPower, Colors.indigo)),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [_choice('lion', 'الأسد x2'), _choice('tiger', 'النمر x2'), _choice('draw', 'تعادل x8')]),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('الرهان:'),
                  Expanded(
                    child: Slider(
                      min: 50,
                      max: 400,
                      divisions: 14,
                      value: _bet.toDouble(),
                      onChanged: (v) => setState(() => _bet = v.round()),
                    ),
                  ),
                  Text('$_bet'),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)),
                child: Text(_result, textAlign: TextAlign.center),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _fight, child: const Text('ابدأ المواجهة')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _powerCard(String title, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: value / 100, minHeight: 10, borderRadius: BorderRadius.circular(20)),
          const SizedBox(height: 8),
          Text('القوة: $value'),
        ],
      ),
    );
  }
}
