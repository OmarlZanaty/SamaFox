import 'package:flutter/material.dart';

import '../../repositories/neon_fortune_repository.dart';
import 'neon_fortune_strings.dart';
import 'neon_fortune_symbols.dart';

/// خزنة الأضواء — Vault of Lights.
///
/// The layout arrives fully decided from the server: which capsule holds which
/// tier icon, and whether any tier reaches three. Tapping only *reveals* — the
/// order cannot change the outcome, because at most one tier is ever placed
/// three times and nine picks always uncover the whole grid. That is what makes
/// this honest rather than a near-miss trap.
class NeonVaultOverlay extends StatefulWidget {
  const NeonVaultOverlay({
    super.key,
    required this.vault,
    required this.reducedMotion,
    required this.onFinished,
  });

  final NeonVaultRound vault;
  final bool reducedMotion;
  final VoidCallback onFinished;

  @override
  State<NeonVaultOverlay> createState() => _NeonVaultOverlayState();
}

class _NeonVaultOverlayState extends State<NeonVaultOverlay> {
  final Set<int> _revealed = {};
  bool _settled = false;

  Map<String, int> get _counts {
    final counts = <String, int>{};
    for (final i in _revealed) {
      final v = widget.vault.capsules[i];
      if (v != 'SPARKLE') counts[v] = (counts[v] ?? 0) + 1;
    }
    return counts;
  }

  String? get _completedTier {
    for (final e in _counts.entries) {
      if (e.value >= 3) return e.key;
    }
    return null;
  }

  void _tap(int index) {
    if (_settled || _revealed.contains(index)) return;
    setState(() => _revealed.add(index));

    if (_completedTier != null || _revealed.length >= widget.vault.capsules.length) {
      setState(() => _settled = true);
    }
  }

  /// Reveals everything at once, for players who would rather not tap nine times.
  void _revealAll() {
    setState(() {
      for (var i = 0; i < widget.vault.capsules.length; i++) {
        _revealed.add(i);
        if (_completedTier != null) break;
      }
      _settled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = NeonStrings.of(context);
    final tier = _completedTier;
    final picksLeft = widget.vault.capsules.length - _revealed.length;

    return Directionality(
      textDirection: s.direction,
      child: Container(
        color: kNeonInk.withValues(alpha: 0.94),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.vaultName,
                  style: const TextStyle(
                    color: kNeonGold,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: kNeonMagenta, blurRadius: 18)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _settled
                      ? (tier != null ? s.vaultWon : s.vaultMissed)
                      : s.vaultInstructions,
                  style: const TextStyle(color: kNeonTextDim, fontSize: 13.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                if (!_settled)
                  Text(
                    s.remaining(picksLeft),
                    style: const TextStyle(color: kNeonCyan, fontSize: 12),
                  ),
                const SizedBox(height: 18),
                _progress(s),
                const SizedBox(height: 18),
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.vault.capsules.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemBuilder: (context, i) => _capsule(s, i),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_settled) ...[
                  Text(
                    tier != null ? s.tier(tier) : s.consolation,
                    style: TextStyle(
                      color: tier != null ? (kJackpotColors[tier] ?? kNeonGold) : kNeonCyan,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.coins(neonCoins(widget.vault.amount)),
                    style: const TextStyle(
                      color: kNeonGold,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kNeonLime,
                        foregroundColor: kNeonInk,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: widget.onFinished,
                      child: Text(
                        s.carryOn,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ] else
                  TextButton(
                    onPressed: _revealAll,
                    child: Text(
                      s.revealAll,
                      style: const TextStyle(color: kNeonCyan, fontSize: 15),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(NeonStrings s) {
    final counts = _counts;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: kJackpotTiers.map((tier) {
        final n = counts[tier] ?? 0;
        final color = kJackpotColors[tier] ?? kNeonGold;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kNeonPlum.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: n > 0 ? 0.9 : 0.3)),
          ),
          child: Column(
            children: [
              Icon(kJackpotIcons[tier], color: color, size: 16),
              const SizedBox(height: 2),
              Text(
                '$n/3',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _capsule(NeonStrings s, int i) {
    final revealed = _revealed.contains(i);
    final content = widget.vault.capsules[i];
    final isTier = content != 'SPARKLE';
    final color = isTier ? (kJackpotColors[content] ?? kNeonGold) : kNeonCyan;

    return GestureDetector(
      onTap: () => _tap(i),
      child: AnimatedContainer(
        duration: Duration(milliseconds: widget.reducedMotion ? 0 : 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: RadialGradient(
            colors: revealed
                ? [color.withValues(alpha: 0.4), kNeonPlum]
                : [kNeonViolet.withValues(alpha: 0.35), kNeonInk],
          ),
          border: Border.all(
            color: revealed ? color : kNeonViolet.withValues(alpha: 0.6),
            width: revealed ? 2 : 1.2,
          ),
          boxShadow: revealed
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16)]
              : null,
        ),
        child: Center(
          child: revealed
              ? (isTier
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(kJackpotIcons[content], color: color, size: 30),
                        const SizedBox(height: 4),
                        Text(
                          s.tier(content),
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Icon(Icons.auto_awesome, color: kNeonCyan.withValues(alpha: 0.7), size: 26))
              : const Icon(Icons.help_outline_rounded, color: kNeonTextDim, size: 28),
        ),
      ),
    );
  }
}
