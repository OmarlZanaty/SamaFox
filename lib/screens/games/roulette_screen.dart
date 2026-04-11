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

  static const List<int> _wheelOrder = [
    0,
    32,
    15,
    19,
    4,
    21,
    2,
    25,
    17,
    34,
    6,
    27,
    13,
    36,
    11,
    30,
    8,
    23,
    10,
    5,
    24,
    16,
    33,
    1,
    20,
    14,
    31,
    9,
    22,
    18,
    29,
    7,
    28,
    12,
    35,
    3,
    26,
  ];

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
          _finishSpin();
        }
      })
      ..addListener(() {
        if (_isSpinning && mounted) {
          setState(() {});
        }
      });

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
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

  Color _colorForNumber(int number) {
    if (number == 0) return _green;
    return number.isOdd ? _red : _black;
  }

  String _keyForNumber(int number) {
    if (number == 0) return 'green';
    return number.isOdd ? 'red' : 'black';
  }

  String _colorLabel(String colorKey) {
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

  String _betLabel() {
    if (_betNumber != null) return 'رقم ${_betNumber!}';
    if (_betColor != null) return _colorLabel(_betColor!);
    return 'لا يوجد';
  }

  bool get _canSpin {
    final hasBet = _betNumber != null || _betColor != null;
    return !_isSpinning && hasBet && _balance >= _selectedChipAmount;
  }

  void _pickChip(int value) {
    if (_isSpinning) return;
    setState(() => _selectedChipAmount = value);
  }

  void _pickNumber(int value) {
    if (_isSpinning) return;
    setState(() {
      _betNumber = value;
      _betColor = null;
    });
  }

  void _pickColor(String value) {
    if (_isSpinning) return;
    setState(() {
      _betColor = value;
      _betNumber = null;
    });
  }

  void _startSpin() {
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
    _startRollingNumbers();
  }

  void _startRollingNumbers() {
    void tick() {
      if (!_isSpinning) return;

      final t = Curves.decelerate.transform(_spinController.value);
      final nearEnd = t > 0.72;
      setState(() {
        if (nearEnd) {
          final jitter = _random.nextInt(7) - 3;
          _displayNumber = (_targetResult + jitter) % 37;
          if (_displayNumber < 0) _displayNumber += 37;
        } else {
          _displayNumber = _random.nextInt(37);
        }
      });

      final delayMs = (40 + (t * 430)).toInt();
      _rollTimer = Timer(Duration(milliseconds: delayMs), tick);
    }

    tick();
  }

  void _finishSpin() {
    _rollTimer?.cancel();

    final result = _targetResult;
    final resultColor = _keyForNumber(result);
    int payout = 0;

    if (_betNumber != null && _betNumber == result) {
      payout = _selectedChipAmount * 10;
    } else if (_betColor != null && _betColor == resultColor) {
      payout = _selectedChipAmount * 2;
    }

    if (payout > 0) _balance += payout;

    setState(() {
      _isSpinning = false;
      _lastResult = result;
      _lastResultColor = resultColor;
      _displayNumber = result;
      _showResult = true;
      _resultMessage = payout > 0 ? 'فزت! +$payout كوين' : 'خسرت 😔';

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

  Widget _buildWheelStage() {
    final spinValue = Curves.decelerate.transform(_spinController.value);
    final rotation = _spinController.value * (pi * 14);
    final ballRotation = -_spinController.value * (pi * 18) + (pi / 3);
    final lightPulse = 0.45 + (sin(_spinController.value * pi * 8) + 1) * 0.2;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 370,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.2,
              colors: [Color(0xFF2B0D4D), Color(0xFF0B0318), Colors.black],
            ),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.purpleAccent.withOpacity(_isSpinning ? 0.35 : 0.2),
                blurRadius: _isSpinning ? 38 : 20,
                spreadRadius: _isSpinning ? 3 : 0,
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(320),
                    painter: _RouletteWheelPainter(
                      rotation: rotation,
                      wheelOrder: _wheelOrder,
                      getColor: _colorForNumber,
                    ),
                  ),
                  Transform.rotate(
                    angle: ballRotation,
                    child: Align(
                      alignment: const Alignment(0.0, -0.82),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.9),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFF5F5F5), Color(0xFF8D8D8D), Color(0xFF444444)],
                        stops: [0.0, 0.55, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 8,
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.95),
                              Colors.grey.shade300,
                              Colors.grey.shade700,
                            ],
                          ),
                          border: Border.all(color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 58,
          child: Container(
            width: 190,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              _isSpinning ? 'SPINNING' : 'READY',
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: TextStyle(
              color: _colorForNumber(_displayNumber),
              fontWeight: FontWeight.w900,
              fontSize: _isSpinning ? 42 : 46,
              shadows: [
                Shadow(
                  color: _colorForNumber(_displayNumber)
                      .withOpacity(_isSpinning ? lightPulse : 0.45),
                  blurRadius: _isSpinning ? 24 : 12,
                ),
              ],
            ),
            child: Text('$_displayNumber'),
          ),
        ),
        if (_showResult && _resultMessage != null)
          FadeTransition(
            opacity: CurvedAnimation(parent: _resultController, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.78, end: 1.06).animate(
                CurvedAnimation(parent: _resultController, curve: Curves.easeOutBack),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _resultMessage!.startsWith('فزت')
                          ? Colors.greenAccent.withOpacity(0.7)
                          : Colors.redAccent.withOpacity(0.7),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  _resultMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        if (_isSpinning)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.04 * (1 - spinValue)),
                      Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildColorButton(String key, String label, Color color) {
    final selected = _betColor == key;
    return Expanded(
      child: GestureDetector(
        onTap: _isSpinning ? null : () => _pickColor(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.amber : Colors.white24,
              width: selected ? 2.3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.6),
                      blurRadius: 14,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberCell(int value) {
    final selected = _betNumber == value;
    return GestureDetector(
      onTap: _isSpinning ? null : () => _pickNumber(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _colorForNumber(value),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.amber : Colors.white12,
            width: selected ? 2.2 : 0.8,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.6),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildChip(int amount) {
    final selected = _selectedChipAmount == amount;
    return Expanded(
      child: GestureDetector(
        onTap: _isSpinning ? null : () => _pickChip(amount),
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
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? Colors.amber : Colors.white24,
              width: selected ? 2.3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.55),
                      blurRadius: 13,
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
    final gridNumbers = List<int>.generate(36, (i) => i + 1);

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
              _buildWheelStage(),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'رهانك: ${_betLabel()}  |  مبلغ: $_selectedChipAmount',
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
                        child: Row(children: [Expanded(child: _buildNumberCell(0))]),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.builder(
                          itemCount: gridNumbers.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemBuilder: (context, index) =>
                              _buildNumberCell(gridNumbers[index]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [_buildChip(10), _buildChip(50), _buildChip(100)]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSpin ? _startSpin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _canSpin
                            ? const [Color(0xFFB266FF), Color(0xFF6D28D9)]
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

class _RouletteWheelPainter extends CustomPainter {
  final double rotation;
  final List<int> wheelOrder;
  final Color Function(int number) getColor;

  _RouletteWheelPainter({
    required this.rotation,
    required this.wheelOrder,
    required this.getColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final bowlPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2A2A2A),
          const Color(0xFF121212),
          Colors.black.withOpacity(0.95),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: radius));

    canvas.drawCircle(c, radius, bowlPaint);

    canvas.drawCircle(
      c,
      radius * 0.98,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.03
        ..color = const Color(0xFFB58B3E).withOpacity(0.9),
    );

    final pocketsOuter = radius * 0.9;
    final pocketsInner = radius * 0.72;
    final segment = (2 * pi) / wheelOrder.length;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);

    for (int i = 0; i < wheelOrder.length; i++) {
      final n = wheelOrder[i];
      final start = -pi / 2 + i * segment;

      final rect = Rect.fromCircle(center: Offset.zero, radius: pocketsOuter);
      final paint = Paint()..color = getColor(n);
      canvas.drawArc(rect, start + 0.01, segment - 0.02, true, paint);

      final innerCut = Paint()..color = const Color(0xFF2B2B2B);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: pocketsInner),
        start + 0.02,
        segment - 0.04,
        true,
        innerCut,
      );

      final textAngle = start + segment / 2;
      final textRadius = (pocketsOuter + pocketsInner) / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: '$n',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.rotate(textAngle + pi / 2);
      tp.paint(
        canvas,
        Offset(-tp.width / 2, -textRadius - tp.height / 2),
      );
      canvas.restore();
    }

    canvas.restore();

    final centerDisc = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withOpacity(0.9),
          const Color(0xFF141414),
          const Color(0xFF000000),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: radius * 0.55));

    canvas.drawCircle(c, radius * 0.56, centerDisc);

    canvas.drawCircle(
      c,
      radius * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant _RouletteWheelPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
