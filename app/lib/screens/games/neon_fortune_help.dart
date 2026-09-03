import 'package:flutter/material.dart';

import '../../repositories/neon_fortune_repository.dart';
import 'neon_fortune_strings.dart';
import 'neon_fortune_symbols.dart';

/// Paytable, feature rules, fairness and the honest money copy for نيون فورتشن.
///
/// The copy here says what the game actually does: it moves the same coins as
/// every other game in SamaFox. There is deliberately no "virtual points / no
/// monetary value" claim on top of a purchasable balance — see §0.1 of
/// docs/neon-fortune-design-review.md.
class NeonFortuneHelp extends StatelessWidget {
  const NeonFortuneHelp({
    super.key,
    required this.layout,
    required this.jackpots,
    required this.lucky,
  });

  final NeonLayout layout;
  final Map<String, int> jackpots;
  final NeonLuckyDrop lucky;

  static Future<void> show(
    BuildContext context, {
    required NeonLayout layout,
    required Map<String, int> jackpots,
    required NeonLuckyDrop lucky,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NeonFortuneHelp(layout: layout, jackpots: jackpots, lucky: lucky),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = NeonStrings.of(context);
    return Directionality(
      textDirection: s.direction,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kNeonPlum, kNeonInk],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: kNeonViolet, width: 2)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: kNeonTextDim.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _Title(s.fullTitle),
              _Body(s.helpIntro),
              const SizedBox(height: 18),
              _Section(s.paytableHeading),
              _Body(s.paytableNote),
              const SizedBox(height: 10),
              _paytable(s),
              const SizedBox(height: 18),
              _Section(s.specialsHeading),
              _rule(s.symbol('WILD'), s.wildRule),
              _rule(
                s.symbol('SCATTER'),
                s.scatterRule(layout.scatterTrigger, layout.freeSpinsAwarded),
              ),
              _rule(s.symbol('TOKEN'), s.tokenRule(layout.tokenTrigger)),
              const SizedBox(height: 18),
              _Section(s.rushName),
              _Body(
                s.rushRules(
                  layout.freeSpinsAwarded,
                  layout.scatterTrigger,
                  layout.freeSpinsRetrigger,
                  layout.freeSpinsCap,
                ),
              ),
              const SizedBox(height: 18),
              _Section(s.vaultName),
              _Body(s.vaultRules(layout.vaultCapsules, layout.vaultConsolationMult)),
              const SizedBox(height: 18),
              _Section(s.jackpotsHeading),
              _Body(s.jackpotsNote),
              const SizedBox(height: 10),
              ...kJackpotTiers.map((tier) => _jackpotRow(s, tier)),
              const SizedBox(height: 18),
              _Section(s.luckyDrop),
              _Body(
                s.luckyDropRules(
                  neonCoins(lucky.reward),
                  s.duration(Duration(milliseconds: lucky.cooldownMs)),
                ),
              ),
              const SizedBox(height: 18),
              _Section(s.fairnessHeading),
              _Body(s.fairnessBody),
              const SizedBox(height: 8),
              _Body(s.rtpBody),
              const SizedBox(height: 18),
              _Section(s.coinsHeading),
              _Body(s.coinsBody),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    s.close,
                    style: const TextStyle(color: kNeonCyan, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paytable(NeonStrings s) {
    final rows = layout.paySymbols.isEmpty ? kNeonSymbols.keys.toList() : layout.paySymbols;
    return Container(
      decoration: BoxDecoration(
        color: kNeonInk.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kNeonViolet.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  s.symbolColumn,
                  style: const TextStyle(color: kNeonTextDim, fontSize: 12),
                ),
              ),
              const _Head('×3'),
              const _Head('×4'),
              const _Head('×5'),
            ],
          ),
          const Divider(color: Colors.white24, height: 14),
          ...rows.map((id) {
            final pays = layout.paytable[id] ?? const [0.0, 0.0, 0.0];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: NeonSymbolTile(symbol: id, compact: true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.symbol(id),
                      style: const TextStyle(color: kNeonText, fontSize: 13),
                    ),
                  ),
                  ...pays.map((p) => _Cell(p)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _jackpotRow(NeonStrings s, String tier) {
    final color = kJackpotColors[tier] ?? kNeonGold;
    final rate = layout.contributionRate[tier];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(kJackpotIcons[tier], color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.tier(tier),
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          if (rate != null)
            Text(
              s.contributionOf((rate * 100).toStringAsFixed(2)),
              style: const TextStyle(color: kNeonTextDim, fontSize: 11),
            ),
          const SizedBox(width: 10),
          Text(
            neonCoins(jackpots[tier] ?? 0),
            style: const TextStyle(color: kNeonGold, fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _rule(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: kNeonCyan, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(color: kNeonTextDim, fontSize: 13, height: 1.5)),
          ],
        ),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: kNeonText, fontSize: 20, fontWeight: FontWeight.w900),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(color: kNeonMagenta, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: kNeonTextDim, fontSize: 13.5, height: 1.6),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kNeonTextDim, fontSize: 12),
        ),
      );
}

class _Cell extends StatelessWidget {
  const _Cell(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Text(
          value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kNeonGold,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
}
