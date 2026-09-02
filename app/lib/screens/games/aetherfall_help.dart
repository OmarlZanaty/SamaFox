import 'package:flutter/material.dart';

import '../../repositories/aetherfall_repository.dart';
import 'aetherfall_symbols.dart';

const _midnight = Color(0xFF0B1030);
const _cyan = Color(0xFF4DD8E6);
const _ember = Color(0xFFFF8A3D);

/// Help panel: rules, live paytable, feature explanations and the free-play
/// notice. Everything here must stay in sync with the server's actual layout,
/// so it renders straight from [AetherfallLayout] rather than hard-coded copy.
class AetherfallHelpSheet extends StatelessWidget {
  const AetherfallHelpSheet({super.key, required this.layout});

  final AetherfallLayout layout;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _midnight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'HOW TO PLAY',
              style: TextStyle(color: _cyan, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            _section(
              'Igniting a tumble',
              'Set your virtual bet and tap IGNITE. The chambers populate with '
                  'symbols and any qualifying win dissolves and refills automatically '
                  '— a spin can chain several tumbles in a row.',
            ),
            _section(
              'Anywhere wins',
              'Symbols pay anywhere on the ${layout.cols}×${layout.rows} board — they do '
                  'not need to line up or touch. Landing ${layout.minMatch} or more of the '
                  'same symbol (Prism Wilds count toward every symbol) triggers a win for '
                  'that symbol.',
            ),
            const SizedBox(height: 18),
            const Text(
              'PAYTABLE',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            _paytable(),
            const SizedBox(height: 18),
            const Text(
              'FEATURES',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            _section(
              'Prism Wild',
              'Substitutes for all eight standard symbols to help complete a win. It '
                  'never substitutes for the Vault Key.',
            ),
            _section(
              'Vault Key & the Skyfire Vault',
              '${layout.vaultKeyTrigger} or more Vault Keys on the very first grid of a spin '
                  'open the Skyfire Vault bonus: ${layout.vaultBonusStartTumbles} free tumbles. '
                  'During the bonus, ${layout.vaultRetriggerKeys} Vault Keys on a single free '
                  'tumble add ${layout.vaultRetriggerTumbles} more tumbles.',
            ),
            _section(
              'Ember Charge',
              'Charge capsules collected during a winning tumble show a percentage value. '
                  'In base play, every charge collected across a sequence is summed and applied '
                  'once as a bonus to that sequence\'s win. In the Skyfire Vault, charge collects '
                  'in a persistent Charge Bank and is applied once to the whole bonus total at the end.',
            ),
            _section(
              'Constellation Lock',
              'Skyfire Vault only. Each winning tumble locks one random symbol cell. Once '
                  '${layout.constellationLockTarget} cells lock, you receive a free Starburst Tumble '
                  'with a guaranteed Prism Wild, and the lock count resets.',
            ),
            const SizedBox(height: 18),
            const Text(
              'CONTROLS & SAFETY',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            _section(
              'AUTO DEMO',
              'Repeats IGNITE at your current bet automatically. Tap STOP at any time to end it immediately.',
            ),
            _section(
              'Sound & motion',
              'Mute music/SFX independently, or enable reduced motion to remove camera shake and flashing effects from the settings panel.',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _ember.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _ember.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'DEMO / FREE PLAY — Aetherfall uses virtual credits only. It has no monetary '
                'value, implies no real odds or RTP, and is entertainment only.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5)),
          ],
        ),
      );

  /// Payouts come off the server's table, so they can carry two decimals (0.95)
  /// or none at all (135). Show what the table actually says — rounding to one
  /// decimal here would print x0.9 for a symbol that really pays 0.95.
  static String _payout(num v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Widget _paytable() {
    final rows = layout.standardSymbols;
    return Column(
      children: [
        for (final sym in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 30, height: 30, child: SymbolTile(symbol: sym)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    kSymbolNames[sym] ?? sym,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
                for (final v in layout.paytable[sym] ?? const [0, 0, 0])
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'x${_payout(v)}',
                      style: const TextStyle(color: _cyan, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(width: 40),
              Expanded(child: SizedBox()),
              _BandLabel('9-11'),
              _BandLabel('12-14'),
              _BandLabel('15+'),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandLabel extends StatelessWidget {
  const _BandLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: 54,
        margin: const EdgeInsets.only(left: 6),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      );
}
