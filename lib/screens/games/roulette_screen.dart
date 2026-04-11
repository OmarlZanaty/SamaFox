import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key});

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen>
    with TickerProviderStateMixin {
  int _balance = 1000;
  int _selectedChipAmount = 10;
  int? _betNumber;
  String? _betColor;
  bool _isSpinning = false;
  int? _lastResult;
  String? _lastResultColor;
  String? _resultMessage;
  bool _showResult = false;
  List<Map<String, dynamic>> _history = []; // {number, color}
  late AnimationController _spinController;
  late AnimationController _resultController;
  int _displayNumber = 0;
  Timer? _rollTimer;

  final Random _random = Random();
  Timer? _overlayTimer;
  int _targetResult = 0;

  static const Color _bg = Color(0xFF0D001A);
  static const Color _appBar = Color(0xFF1a0533);
  static const Color _red = Color(0xFFB91C1C);
  static const Color _black = Color(0xFF1C1C1C);
  static const Color _green = Color(0xFF166534);

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _completeSpin();
        }
      })
      ..addListener(() {
        if (mounted && _isSpinning) {
          setState(() {});
        }
      });

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _overlayTimer?.cancel();
    _spinController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  bool get _canSpin {
    final hasBet = _betNumber != null || _betColor != null;
    return !_isSpinning && hasBet && _balance >= _selectedChipAmount;
  }

  Color _colorForNumber(int number) {
    if (number == 0) return _green;
    return number.isOdd ? _red : _black;
  }

  String _keyForNumber(int number) {
    if (number == 0) return 'green';
    return number.isOdd ? 'red' : 'black';
  }

  Color _colorFromKey(String key) {
    switch (key) {
      case 'red':
        return _red;
      case 'black':
        return _black;
      case 'green':
        return _green;
      default:
        return Colors.white;
    }
  }

  String _labelForColor(String key) {
    switch (key) {
      case 'red':
        return 'أحمر';
      case 'black':
        return 'أسود';
      case 'green':
        return 'أخضر';
      default:
        return '-';
    }
  }

  String _betText() {
    if (_betNumber != null) return 'رقم ${_betNumber!}';
    if (_betColor != null) return _labelForColor(_betColor!);
    return 'لا يوجد';
  }

  void _pickChip(int amount) {
    if (_isSpinning) return;
    setState(() => _selectedChipAmount = amount);
  }

  void _pickNumber(int number) {
    if (_isSpinning) return;
    setState(() {
      _betNumber = number;
      _betColor = null;
    });
  }

  void _pickColor(String color) {
    if (_isSpinning) return;
    setState(() {
      _betColor = color;
      _betNumber = null;
    });
  }

  void _spin() {
    if (!_canSpin) return;

    _targetResult = _random.nextInt(37);
    _rollTimer?.cancel();
    _overlayTimer?.cancel();

    setState(() {
      _balance -= _selectedChipAmount;
      _isSpinning = true;
      _showResult = false;
      _resultMessage = null;
    });

    _resultController.reset();
    _spinController.forward(from: 0);
    _startRollingTicker();
  }

  void _startRollingTicker() {
    void tick() {
      if (!_isSpinning) return;

      final t = Curves.decelerate.transform(_spinController.value);
      final closeness = t > 0.7;

      setState(() {
        if (closeness) {
          final jitter = _random.nextInt(7) - 3;
          _displayNumber = (_targetResult + jitter) % 37;
          if (_displayNumber < 0) _displayNumber += 37;
        } else {
          _displayNumber = _random.nextInt(37);
        }
      });

      final delay = (45 + (t * 420)).toInt();
      _rollTimer = Timer(Duration(milliseconds: delay), tick);
    }

    tick();
  }

  void _completeSpin() {
    _rollTimer?.cancel();

    final result = _targetResult;
    final resultColor = _keyForNumber(result);

    bool isWin = false;
    int payout = 0;

    if (_betNumber != null && _betNumber == result) {
      isWin = true;
      payout = _selectedChipAmount * 10;
    } else if (_betColor != null && _betColor == resultColor) {
      isWin = true;
      payout = _selectedChipAmount * 2;
    }

    if (isWin) {
      _balance += payout;
    }

    setState(() {
      _isSpinning = false;
      _lastResult = result;
      _lastResultColor = resultColor;
      _displayNumber = result;
      _resultMessage = isWin ? 'فزت! +$payout كوين' : 'خسرت 😔';
      _showResult = true;

      _history.insert(0, {'number': result, 'color': resultColor});
      if (_history.length > 10) {
        _history = _history.take(10).toList();
      }
    });

    _resultController
      ..reset()
      ..forward();

    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showResult = false);
    });
  }

  Widget _buildStage() {
    final spinT = Curves.decelerate.transform(_spinController.value);
    final wheelRotation = _spinController.value * (pi * 11);
    final wobble = sin(_spinController.value * pi * 12) * (0.07 * (1 - spinT));
    final pulse = 0.45 + ((sin(_spinController.value * pi * 8) + 1) / 2) * 0.4;
    final currentColor = _colorForNumber(_displayNumber);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1A0533),
                const Color(0xFF120225),
                Colors.black.withOpacity(0.9),
              ],
            ),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: currentColor.withOpacity(_isSpinning ? 0.35 : 0.22),
                blurRadius: _isSpinning ? 40 : 20,
                spreadRadius: _isSpinning ? 4 : 1,
              ),
            ],
          ),
        ),
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(0.33 + wobble)
            ..rotateZ(wheelRotation),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  const Color(0xFFE11D48),
                  const Color(0xFF111827),
                  const Color(0xFF16A34A),
                  const Color(0xFF111827),
                  const Color(0xFFE11D48),
                ],
                transform: GradientRotation(wheelRotation * 0.25),
              ),
              border: Border.all(color: Colors.white30, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(_isSpinning ? pulse : 0.25),
                  blurRadius: _isSpinning ? 28 : 12,
                  spreadRadius: _isSpinning ? 2 : 0,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.65),
                  border: Border.all(color: Colors.white24),
                ),
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 120),
                  style: TextStyle(
                    color: currentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: _isSpinning ? 30 : 34,
                    shadows: [
                      Shadow(
                        color: currentColor.withOpacity(0.9),
                        blurRadius: _isSpinning ? 20 : 8,
                      ),
                    ],
                  ),
                  child: Text('$_displayNumber'),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.9),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        if (_showResult && _resultMessage != null)
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _resultController,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.78, end: 1.06).animate(
                CurvedAnimation(
                  parent: _resultController,
                  curve: Curves.easeOutBack,
                ),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: (_resultMessage!.startsWith('فزت')
                          ? Colors.greenAccent
                          : Colors.redAccent)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _resultMessage!.startsWith('فزت')
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _resultMessage!.startsWith('فزت')
                          ? Colors.greenAccent.withOpacity(0.65)
                          : Colors.redAccent.withOpacity(0.65),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  _resultMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildColorButton(String key, String text, Color color) {
    final selected = _betColor == key;
    return Expanded(
      child: GestureDetector(
        onTap: _isSpinning ? null : () => _pickColor(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.amber : Colors.white24,
              width: selected ? 2.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.65),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberCell(int n) {
    final selected = _betNumber == n;
    return GestureDetector(
      onTap: _isSpinning ? null : () => _pickNumber(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _colorForNumber(n),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.amber : Colors.white12,
            width: selected ? 2.4 : 0.8,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.65),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildChip(int value) {
    final selected = _selectedChipAmount == value;
    return Expanded(
      child: GestureDetector(
        onTap: _isSpinning ? null : () => _pickChip(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7E22CE), Color(0xFF4C1D95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? Colors.amber : Colors.white24,
              width: selected ? 2.4 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: Colors.amber.withOpacity(0.55),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numbers = List.generate(36, (i) => i + 1);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _appBar,
        centerTitle: true,
        title: const Text('روليت 🎰'),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF311152),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(
                  '$_balance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _buildStage(),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'رهانك: ${_betText()}  |  مبلغ: $_selectedChipAmount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildColorButton('red', 'Red', _red),
                  const SizedBox(width: 8),
                  _buildColorButton('black', 'Black', _black),
                  const SizedBox(width: 8),
                  _buildColorButton('green', 'Green', _green),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [Expanded(child: _buildNumberCell(0))],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          itemCount: numbers.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, i) =>
                              _buildNumberCell(numbers[i]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [_buildChip(10), _buildChip(50), _buildChip(100)],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSpin ? _spin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _canSpin
                            ? const [Color(0xFFB266FF), Color(0xFF6D28D9)]
                            : [Colors.grey.shade700, Colors.grey.shade800],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        if (_canSpin)
                          BoxShadow(
                            color: Colors.purpleAccent.withOpacity(0.45),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _isSpinning ? '...SPINNING' : 'SPIN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'آخر 10 نتائج',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: _history.isEmpty
                    ? Center(
                        child: Text(
                          'لا يوجد نتائج بعد',
                          style: TextStyle(color: Colors.white.withOpacity(0.55)),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final item = _history[i];
                          return Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _colorFromKey(item['color'] as String),
                              border: Border.all(color: Colors.white24),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item['number']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
