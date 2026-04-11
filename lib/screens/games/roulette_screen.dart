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
  List<Map<String, dynamic>> _history = [];
  late AnimationController _spinController;
  late AnimationController _resultController;
  int _displayNumber = 0;
  Timer? _rollTimer;
  Timer? _resultOverlayTimer;

  final Random _random = Random();

  static const Color _bgColor = Color(0xFF0D001A);
  static const Color _appBarColor = Color(0xFF1a0533);
  static const Color _redCell = Color(0xFFB91C1C);
  static const Color _blackCell = Color(0xFF1C1C1C);
  static const Color _greenCell = Color(0xFF166534);

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _finishSpin();
        }
      });

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _resultOverlayTimer?.cancel();
    _spinController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  Color _getColorForNumber(int number) {
    if (number == 0) return _greenCell;
    return number.isOdd ? _redCell : _blackCell;
  }

  String _getColorName(String colorKey) {
    switch (colorKey) {
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

  Color _getColorFromKey(String colorKey) {
    switch (colorKey) {
      case 'red':
        return _redCell;
      case 'black':
        return _blackCell;
      case 'green':
        return _greenCell;
      default:
        return Colors.white;
    }
  }

  String _currentBetText() {
    if (_betNumber != null) return _betNumber.toString();
    if (_betColor != null) return _getColorName(_betColor!);
    return 'لا يوجد';
  }

  bool get _canSpin {
    final hasBet = _betNumber != null || _betColor != null;
    return !_isSpinning && hasBet && _balance >= _selectedChipAmount;
  }

  void _placeNumberBet(int number) {
    if (_isSpinning) return;
    setState(() {
      _betNumber = number;
      _betColor = null;
    });
  }

  void _placeColorBet(String colorKey) {
    if (_isSpinning) return;
    setState(() {
      _betColor = colorKey;
      _betNumber = null;
    });
  }

  void _startSpin() {
    if (!_canSpin) return;

    setState(() {
      _balance -= _selectedChipAmount;
      _isSpinning = true;
      _showResult = false;
      _resultMessage = null;
    });

    _resultController.reset();
    _spinController.reset();

    _rollTimer?.cancel();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isSpinning) return;
      final t = Curves.decelerate.transform(_spinController.value);
      final intervalMs = (50 + (t * 380)).toInt();
      timer.cancel();

      _displayNumber = _random.nextInt(37);
      if (mounted) setState(() {});

      _rollTimer = Timer.periodic(Duration(milliseconds: intervalMs), (next) {
        if (!_isSpinning) {
          next.cancel();
          return;
        }
        _displayNumber = _random.nextInt(37);
        if (mounted) setState(() {});
        final progress = Curves.decelerate.transform(_spinController.value);
        final newInterval = (50 + (progress * 380)).toInt();
        if (newInterval != intervalMs) {
          next.cancel();
          _rollTimer = Timer.periodic(
            Duration(milliseconds: newInterval),
            (rolling) {
              if (!_isSpinning) {
                rolling.cancel();
                return;
              }
              _displayNumber = _random.nextInt(37);
              if (mounted) setState(() {});
            },
          );
        }
      });
    });

    _spinController.forward();
  }

  void _finishSpin() {
    _rollTimer?.cancel();

    final result = _random.nextInt(37);
    final resultColorKey = result == 0
        ? 'green'
        : (result.isOdd ? 'red' : 'black');

    bool isWin = false;
    int payout = 0;

    if (_betNumber != null && _betNumber == result) {
      isWin = true;
      payout = _selectedChipAmount * 10;
    } else if (_betColor != null && _betColor == resultColorKey) {
      isWin = true;
      payout = _selectedChipAmount * 2;
    }

    if (isWin) {
      _balance += payout;
    }

    setState(() {
      _isSpinning = false;
      _lastResult = result;
      _lastResultColor = resultColorKey;
      _displayNumber = result;
      _showResult = true;
      _resultMessage = isWin ? 'فزت! +$payout كوين' : 'خسرت 😔';

      _history.insert(0, {'number': result, 'color': resultColorKey});
      if (_history.length > 10) {
        _history = _history.take(10).toList();
      }
    });

    _resultController
      ..reset()
      ..forward();

    _resultOverlayTimer?.cancel();
    _resultOverlayTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showResult = false;
      });
    });
  }

  Widget _buildColorButton({
    required String keyValue,
    required String label,
    required Color color,
  }) {
    final selected = _betColor == keyValue;
    return GestureDetector(
      onTap: _isSpinning ? null : () => _placeColorBet(keyValue),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 1 : 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.amber : Colors.white24,
            width: selected ? 2.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.6),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberCell(int number) {
    final isSelected = _betNumber == number;
    final cellColor = _getColorForNumber(number);

    return GestureDetector(
      onTap: _isSpinning ? null : () => _placeNumberBet(number),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cellColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white12,
            width: isSelected ? 2.5 : 0.7,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.65),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildChipButton(int amount) {
    final isSelected = _selectedChipAmount == amount;
    return Expanded(
      child: GestureDetector(
        onTap: _isSpinning
            ? null
            : () {
                setState(() => _selectedChipAmount = amount);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7E22CE), Color(0xFF4C1D95)],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white24,
              width: isSelected ? 2.2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.65),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$amount',
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
    final numberTiles = List<int>.generate(37, (i) => i);
    final restNumbers = numberTiles.where((n) => n != 0).toList();

    final overlayColor = (_resultMessage?.contains('فزت') ?? false)
        ? Colors.greenAccent
        : Colors.redAccent;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _appBarColor,
        title: const Text('روليت 🎰'),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF311152),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
                const SizedBox(width: 5),
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
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white24),
                      boxShadow: _isSpinning
                          ? [
                              BoxShadow(
                                color: Colors.cyanAccent.withValues(alpha: 0.5),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 140),
                      style: TextStyle(
                        color: _getColorForNumber(_displayNumber),
                        fontSize: _isSpinning ? 56 : 52,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: _getColorForNumber(_displayNumber)
                                .withValues(alpha: 0.7),
                            blurRadius: _isSpinning ? 24 : 12,
                          ),
                        ],
                      ),
                      child: Text('$_displayNumber'),
                    ),
                  ),
                  if (_showResult && _resultMessage != null)
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _resultController,
                        curve: Curves.easeOut,
                      ),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.8, end: 1.05).animate(
                          CurvedAnimation(
                            parent: _resultController,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: overlayColor.withValues(alpha: 0.2),
                            border: Border.all(color: overlayColor, width: 1.2),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: overlayColor.withValues(alpha: 0.5),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            _resultMessage!,
                            style: TextStyle(
                              color: overlayColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'رهانك: ${_currentBetText()}  |  مبلغ: $_selectedChipAmount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildColorButton(
                      keyValue: 'red',
                      label: 'Red',
                      color: _redCell,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildColorButton(
                      keyValue: 'black',
                      label: 'Black',
                      color: _blackCell,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildColorButton(
                      keyValue: 'green',
                      label: 'Green',
                      color: _greenCell,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Expanded(child: _buildNumberCell(0)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: restNumbers.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, index) {
                            final number = restNumbers[index];
                            return _buildNumberCell(number);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildChipButton(10),
                  _buildChipButton(50),
                  _buildChipButton(100),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSpin ? _startSpin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _canSpin
                            ? const [Color(0xFFA855F7), Color(0xFF6D28D9)]
                            : [Colors.grey.shade700, Colors.grey.shade800],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _isSpinning ? '...SPINNING' : 'SPIN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'آخر النتائج',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
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
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final item = _history[index];
                          final color = _getColorFromKey(item['color'] as String);
                          return Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${item['number']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemCount: _history.length,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
