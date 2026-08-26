import 'package:flutter/material.dart';

const _midnight = Color(0xFF0B1030);
const _ember = Color(0xFFFF8A3D);
const _mint = Color(0xFF7CE8B0);
const _cyan = Color(0xFF4DD8E6);

/// Full-screen transition into the Skyfire Vault bonus: keys align, a ribbon
/// of skyfire sweeps across, and the trigger text appears. 2.5–3.5s, with a
/// skip button after 800ms, per the animation-direction spec.
class SkyfireVaultTransition extends StatefulWidget {
  const SkyfireVaultTransition({
    super.key,
    required this.tumbles,
    required this.onDone,
    this.reducedMotion = false,
  });

  final int tumbles;
  final VoidCallback onDone;
  final bool reducedMotion;

  @override
  State<SkyfireVaultTransition> createState() => _SkyfireVaultTransitionState();
}

class _SkyfireVaultTransitionState extends State<SkyfireVaultTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 900 : 3000),
  )..forward();

  bool _canSkip = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _canSkip = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _canSkip ? widget.onDone : null,
      child: Container(
        color: _midnight,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final keyGlow = Curves.easeOut.transform((t * 2).clamp(0, 1).toDouble());
            final textIn = Curves.easeOutBack.transform(((t - 0.4) * 2.5).clamp(0, 1).toDouble());
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: keyGlow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      4,
                      (i) => Transform.rotate(
                        angle: (1 - keyGlow) * 3.14 * (i.isEven ? 1 : -1),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.vpn_key_rounded, color: _cyan, size: 34),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.7 + textIn * 0.3,
                  child: Opacity(
                    opacity: textIn.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'SKYFIRE VAULT',
                          style: TextStyle(
                            color: _ember,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.tumbles} FREE TUMBLES',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_canSkip)
                  Positioned(
                    bottom: 40,
                    child: TextButton(
                      onPressed: widget.onDone,
                      child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Persistent HUD strip shown during bonus play: tumbles left, charge bank,
/// constellation locks.
class BonusHud extends StatelessWidget {
  const BonusHud({
    super.key,
    required this.tumblesLeft,
    required this.chargeBank,
    required this.locks,
    required this.lockTarget,
  });

  final int tumblesLeft;
  final int chargeBank;
  final int locks;
  final int lockTarget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _midnight.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ember.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('TUMBLES LEFT', '$tumblesLeft', _cyan),
          _divider(),
          _stat('CHARGE BANK', '+$chargeBank%', _ember),
          _divider(),
          _stat('LOCKS', '${locks.clamp(0, lockTarget)}/$lockTarget', _mint),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white24,
      );

  Widget _stat(String label, String value, Color color) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1),
          ),
        ],
      );
}

/// A small banner shown when a Starburst Tumble fires (3 constellation locks
/// connected) — a bonus-only free tumble with a guaranteed Prism Wild.
class StarburstBanner extends StatelessWidget {
  const StarburstBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_mint, _cyan]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _mint.withValues(alpha: 0.6), blurRadius: 18)],
      ),
      child: const Text(
        'STARBURST TUMBLE',
        style: TextStyle(
          color: _midnight,
          fontWeight: FontWeight.w900,
          fontSize: 13,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

/// End-of-bonus summary sheet: total credits, highest charge event, cascade
/// count, and a replay button.
class BonusSummarySheet extends StatelessWidget {
  const BonusSummarySheet({
    super.key,
    required this.totalCredits,
    required this.highestCharge,
    required this.cascadeCount,
    required this.onClose,
  });

  final int totalCredits;
  final int highestCharge;
  final int cascadeCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        color: _midnight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: _ember, width: 1.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SKYFIRE VAULT — SUMMARY',
            style: TextStyle(color: _ember, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 18),
          Text(
            '$totalCredits',
            style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
          ),
          const Text(
            'TOTAL VIRTUAL CREDITS',
            style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metric('HIGHEST CHARGE', '+$highestCharge%'),
              _metric('CASCADES', '$cascadeCount'),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: _midnight,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(color: _mint, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
        ],
      );
}
