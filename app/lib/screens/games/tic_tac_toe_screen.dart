import 'package:flutter/material.dart';

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  static const _bg0 = Color(0xFF0D0620);
  static const _bg1 = Color(0xFF1A0E3E);
  static const _brand = Color(0xFF6B4CE6);
  static const _gold = Color(0xFFFFD36E);

  final List<String> _board = List.filled(9, '');
  String _turn = 'X';
  String? _winner; // 'X' or 'O' or 'draw'
  int _xScore = 0;
  int _oScore = 0;

  void _resetBoard() {
    setState(() {
      for (int i = 0; i < 9; i++) _board[i] = '';
      _turn = 'X';
      _winner = null;
    });
  }

  void _resetAll() {
    setState(() {
      _xScore = 0;
      _oScore = 0;
      _resetBoard();
    });
  }

  void _tap(int i) {
    if (_winner != null) return;
    if (_board[i].isNotEmpty) return;

    setState(() {
      _board[i] = _turn;
      _checkWinner();

      if (_winner == null) {
        _turn = _turn == 'X' ? 'O' : 'X';
      } else {
        if (_winner == 'X') _xScore++;
        if (_winner == 'O') _oScore++;
      }
    });
  }

  void _checkWinner() {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];

    for (final l in lines) {
      final a = _board[l[0]];
      final b = _board[l[1]];
      final c = _board[l[2]];
      if (a.isNotEmpty && a == b && b == c) {
        _winner = a;
        return;
      }
    }

    if (_board.every((e) => e.isNotEmpty)) {
      _winner = 'draw';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _winner == null
        ? 'الدور على: ${_turn == 'X' ? 'X' : 'O'}'
        : (_winner == 'draw' ? 'تعادل 🤝' : 'الفائز: $_winner 🎉');

    return Scaffold(
      backgroundColor: _bg1,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('إكس أو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bg1, _bg0]),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Score
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ScorePill(label: 'X', value: _xScore, color: _gold),
                  const SizedBox(width: 10),
                  _ScorePill(label: 'O', value: _oScore, color: _brand),
                  const Spacer(),
                  Text(status, style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w700)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Board
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GridView.builder(
                    itemCount: 9,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (_, i) => _Cell(
                      value: _board[i],
                      onTap: () => _tap(i),
                      highlight: _winner != null,
                    ),
                  ),
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: _Btn(
                      label: 'إعادة الجولة',
                      onTap: _resetBoard,
                      bg: Colors.white.withOpacity(0.12),
                      fg: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Btn(
                      label: 'تصفير النتائج',
                      onTap: _resetAll,
                      bg: _brand,
                      fg: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.onTap, required this.highlight});
  final String value;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isX = value == 'X';
    final color = isX ? const Color(0xFFFFD36E) : const Color(0xFFB55CFF);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
          boxShadow: highlight
              ? [BoxShadow(color: Colors.white.withOpacity(0.08), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: value.isEmpty ? Colors.white.withOpacity(0.10) : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

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
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.22)),
            child: Center(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 8),
          Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
