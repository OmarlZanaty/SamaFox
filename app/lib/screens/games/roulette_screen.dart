import 'dart:math';
import 'package:flutter/material.dart';

class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key});

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> {
  final Random _random = Random();
  int _balance = 1000;
  int _betAmount = 50;
  String _betType = 'red';
  int? _result;
  String _status = 'اختر نوع الرهان واضغط لف العجلة';

  static const List<int> _redNumbers = [
    1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36
  ];

  void _spin() {
    if (_betAmount > _balance) {
      setState(() => _status = 'رصيدك غير كافٍ');
      return;
    }

    final int number = _random.nextInt(37);
    final bool isRed = _redNumbers.contains(number);
    final bool isEven = number != 0 && number.isEven;

    int win = 0;
    if (_betType == 'number' && number == 7) {
      win = _betAmount * 35;
    } else if (_betType == 'red' && isRed) {
      win = _betAmount * 2;
    } else if (_betType == 'black' && number != 0 && !isRed) {
      win = _betAmount * 2;
    } else if (_betType == 'even' && isEven) {
      win = _betAmount * 2;
    } else if (_betType == 'odd' && number != 0 && !isEven) {
      win = _betAmount * 2;
    }

    setState(() {
      _result = number;
      _balance -= _betAmount;
      _balance += win;
      _status = win > 0 ? 'مبروك! ربحت $win عملة' : 'حظ أوفر! حاول مرة أخرى';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isRed = _result != null && _redNumbers.contains(_result);
    return Scaffold(
      appBar: AppBar(title: const Text('روليت')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _BalanceCard(balance: _balance),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Text(_result == null ? '--' : '$_result', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_result == null ? 'لم يتم السحب بعد' : (_result == 0 ? '🟢 أخضر' : isRed ? '🔴 أحمر' : '⚫ أسود')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _betType,
                decoration: const InputDecoration(labelText: 'نوع الرهان', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'red', child: Text('أحمر x2')),
                  DropdownMenuItem(value: 'black', child: Text('أسود x2')),
                  DropdownMenuItem(value: 'even', child: Text('زوجي x2')),
                  DropdownMenuItem(value: 'odd', child: Text('فردي x2')),
                  DropdownMenuItem(value: 'number', child: Text('رقم 7 x35')),
                ],
                onChanged: (value) => setState(() => _betType = value ?? 'red'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('قيمة الرهان:'),
                  Expanded(
                    child: Slider(
                      min: 10,
                      max: 300,
                      divisions: 29,
                      value: _betAmount.toDouble(),
                      label: '$_betAmount',
                      onChanged: (v) => setState(() => _betAmount = v.round()),
                    ),
                  ),
                  Text('$_betAmount'),
                ],
              ),
              Text(_status, textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _spin,
                  icon: const Icon(Icons.casino),
                  label: const Text('لف العجلة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(14)),
      child: Text('الرصيد: $balance', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
