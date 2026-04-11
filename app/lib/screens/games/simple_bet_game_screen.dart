import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/wallet_provider.dart';

typedef RoundResolver = RoundResult Function(Random rng, int bet, String choice);

class RoundResult {
  final bool win;
  final int payout; // coins earned (profit, not including returning bet)
  final String outcomeText;

  const RoundResult({
    required this.win,
    required this.payout,
    required this.outcomeText,
  });
}

class SimpleBetGameScreen extends ConsumerStatefulWidget {
  final String title;
  final List<String> choices;
  final RoundResolver resolve;
  final IconData icon;

  const SimpleBetGameScreen({
    super.key,
    required this.title,
    required this.choices,
    required this.resolve,
    required this.icon,
  });

  @override
  ConsumerState<SimpleBetGameScreen> createState() => _SimpleBetGameScreenState();
}

class _SimpleBetGameScreenState extends ConsumerState<SimpleBetGameScreen> {
  final _rng = Random();

  int bet = 50;
  String? selected;
  String status = "Pick a choice, set bet, then Play.";
  final List<String> history = [];

  void _pushHistory(String line) {
    history.insert(0, line);
    if (history.length > 10) history.removeLast();
  }

  void _play() {
    final wallet = ref.read(walletProvider.notifier);

    if (selected == null) {
      setState(() => status = "Select a choice first.");
      return;
    }
    if (!wallet.canBet(bet)) {
      setState(() => status = "Not enough coins.");
      return;
    }

    // take bet first
    wallet.subtract(bet);

    final result = widget.resolve(_rng, bet, selected!);

    if (result.win) {
      // return bet + payout
      wallet.add(bet + result.payout);
    }

    final line = result.win
        ? "✅ WIN | Bet $bet | +${result.payout} | ${result.outcomeText}"
        : "❌ LOSE | Bet $bet | ${result.outcomeText}";
    setState(() {
      status = line;
      _pushHistory(line);
    });
  }

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0620),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Coins: $coins",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _BetChip(value: 10, selected: bet == 10, onTap: () => setState(() => bet = 10)),
                  _BetChip(value: 50, selected: bet == 50, onTap: () => setState(() => bet = 50)),
                  _BetChip(value: 100, selected: bet == 100, onTap: () => setState(() => bet = 100)),
                  _BetChip(value: 250, selected: bet == 250, onTap: () => setState(() => bet = 250)),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // choices
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Choose:",
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.choices.map((c) {
                final isSel = selected == c;
                return GestureDetector(
                  onTap: () => setState(() => selected = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white.withOpacity(0.20) : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isSel ? Colors.amber : Colors.white24, width: 2),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(color: Colors.white.withOpacity(isSel ? 1 : 0.85), fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // play button + status
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _play,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("PLAY", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),

            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                status,
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 14),

            // history
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Last rounds:",
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    history[i],
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BetChip extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _BetChip({required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black.withOpacity(0.12) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.black : Colors.white24, width: 2),
        ),
        child: Text(
          "$value",
          style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}
