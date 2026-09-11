import 'package:flutter/material.dart';

import '../../repositories/olympus_repository.dart';
import 'olympus_strings.dart';
import 'olympus_symbols.dart';

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);
const _violetDeep = Color(0xFF1A0838);
const _violetMid = Color(0xFF2A1258);

/// Rules, the paytable and responsible-play information.
///
/// Everything here is read from the layout the *server* sent, not from
/// constants duplicated on the client: if the paytable is retuned server-side,
/// this sheet shows the new numbers without an app release. That matters — a
/// help panel that disagrees with the math is worse than no help panel.
class OlympusHelpSheet extends StatelessWidget {
  const OlympusHelpSheet({
    super.key,
    required this.layout,
    required this.strings,
    this.art,
  });

  final OlympusLayout layout;
  final OlympusStrings strings;
  final OlympusArt? art;

  @override
  Widget build(BuildContext context) {
    final s = strings;
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
              colors: [_violetMid, _violetDeep],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: _gold, width: 1.5)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                s.rules,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 18),

              _section(s.howToWin, s.howToWinBody(layout.minMatch)),
              _section(s.tumbleRules, s.tumbleBody),
              _section(
                s.multiplierRules,
                s.multiplierBody(layout.multValues.map((v) => '×$v').join('، ')),
              ),
              _calloutRow(s.multiplierExample),
              _calloutRow(s.multipliersAdd),
              _section(
                s.freeSpinsRules,
                s.freeSpinsBody(
                  layout.scatterTrigger,
                  layout.freeSpins,
                  layout.scatterRetrigger,
                  layout.retriggerSpins,
                ),
              ),
              _section(s.capRule, s.capBody(layout.maxWinMultiple)),

              const SizedBox(height: 10),
              _paytable(),

              const SizedBox(height: 20),
              _specials(),

              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.noStrategy,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.footer,
                      style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _boltBlue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.6),
            ),
          ],
        ),
      );

  Widget _calloutRow(String text) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: _gold, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _paytable() {
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.paytableTitle,
          style: const TextStyle(
            color: _boltBlue,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          s.paytableNote,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              // Header band. The counts are LTR digits in both languages.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
                child: Row(
                  children: [
                    const Spacer(),
                    for (final band in [s.band8, s.band10, s.band12])
                      SizedBox(
                        width: 52,
                        child: Text(
                          band,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              // Most valuable first, so the row a player is hunting is at the
              // top rather than buried under five gems.
              for (final id in layout.standardSymbols.reversed) _payRow(id),
            ],
          ),
        ),
      ],
    );
  }

  Widget _payRow(String id) {
    final values = layout.paytable[id] ?? const [0.0, 0.0, 0.0];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: OlympusSymbolTile(
              symbol: id,
              label: strings.symbol(id),
              art: art?.forSymbol(id),
              badge: id == 'SCATTER' ? strings.scatterBadge : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.symbol(id),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          for (final v in values)
            SizedBox(
              width: 52,
              child: Text(
                _fmt(v),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Trims the trailing zero so 1.50 reads as 1.5 but 0.22 keeps both digits.
  String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
  }

  Widget _specials() {
    final s = strings;
    return Column(
      children: [
        _specialRow(
          'SCATTER',
          s.symbol('SCATTER'),
          s.freeSpinsBody(
            layout.scatterTrigger,
            layout.freeSpins,
            layout.scatterRetrigger,
            layout.retriggerSpins,
          ),
        ),
        const SizedBox(height: 10),
        _specialRow('MULT', s.symbol('MULT'), s.multipliersAdd),
      ],
    );
  }

  Widget _specialRow(String id, String name, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: OlympusSymbolTile(
                symbol: id,
                label: name,
                art: art?.forSymbol(id),
                badge: id == 'SCATTER' ? strings.scatterBadge : null,
                multValue: id == 'MULT' ? 25 : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
