import '../../l10n/tr.dart';
import 'package:flutter/material.dart';

import '../../repositories/asterion_repository.dart';
import 'asterion_art.dart';

/// The rules of أستيريون, in the player's language, with the real numbers.
///
/// Everything here reads from the layout the server sent, so the sheet cannot
/// drift out of date when the paytable is retuned: if the backend changes, this
/// panel changes with it on the next load.
class AsterionHelpSheet extends StatelessWidget {
  const AsterionHelpSheet({super.key, required this.layout});

  final AsterionLayout layout;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF16204A), Color(0xFF070A1B)],
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AsterionPalette.silverDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  tr('أستيريون — كيف تُلعب', "Asterion — how to play"),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              _section(tr('اللوحة', "Board"), [
                tr('لوحة من ${layout.cols} أعمدة × ${layout.rows} صفوف، أي ${layout.cols * layout.rows} خانة.', "A board of ${layout.cols} columns × ${layout.rows} rows, with ${layout.cols * layout.rows} cells."),
                tr('لا توجد خطوط دفع: يكفي أن يظهر ${layout.minMatch} رموز متطابقة أو أكثر في أي مكان على اللوحة.', "No paylines: ${layout.minMatch} or more matching symbols anywhere on the board are enough to win."),
                tr('كل الرموز المتطابقة تُحتسب مرة واحدة، ويمكن أن يفوز أكثر من رمز في نفس اللقطة.', "All matching symbols count once, and more than one symbol type can win in the same frame."),
              ]),

              _section(tr('التساقط', "Tumble"), [
                tr('الرموز الفائزة تتلاشى، وما فوقها يسقط مكانها، وتنزل رموز جديدة من الأعلى.', "Winning symbols disappear, those above fall into place, and new symbols drop from the top."),
                tr('يتكرر ذلك ما دام هناك فوز جديد. مجموع اللقطات كلها هو ربح الجولة قبل المضاعف.', "This repeats while new wins occur. All frames together form the round win before the multiplier."),
              ]),

              _section(tr('كرات العاصفة', "Storm orbs"), [
                tr('كرة العاصفة تحمل قيمة ظاهرة من ${layout.orbValues.first}x إلى ${layout.orbValues.last}x.', "A storm orb carries a visible value from ${layout.orbValues.first}x to ${layout.orbValues.last}x."),
                tr('الكرة لا تدفع وحدها ولا تُحتسب ضمن التطابق، ولا تسقط: تثبت في مكانها حتى تنتهي الجولة.', "Orbs do not pay on their own or count as matches. They do not fall: they stay in place until the round ends."),
                tr('عند توقّف التساقط تُجمع قيم كل الكرات الظاهرة **بالجمع** — 4x + 6x + 25x = 35x وليس 600x — ويُضرب بها ربح الجولة كاملًا.', "When tumbling stops, all visible orb values are **added** — 4x + 6x + 25x = 35x, not 600x — and multiply the entire round win."),
                tr('إذا لم تربح الجولة شيئًا فالكرات تختفي دون أثر.', "If the round wins nothing, the orbs disappear without effect."),
              ]),

              _section(tr('تجارب السماء', "Sky Trials"), [
                tr('${layout.crestTrigger} شعارات أو أكثر في التوزيع الأول تمنحك ${layout.trialSpins} لفة مجانية.', "${layout.crestTrigger} or more crests on the first board grant ${layout.trialSpins} free spins."),
                tr('${layout.crestRetrigger} شعارات أثناء التجارب تضيف ${layout.retriggerSpins} لفّات.', "${layout.crestRetrigger} crests during the trials add ${layout.retriggerSpins} spins."),
                tr('داخل التجارب يوجد عدّاد "مضاعف التجارب": كل كرة تُجمع في لفة رابحة تُضاف إليه، ولا يُصفَّر حتى تنتهي التجارب.', "During trials, every orb collected on a winning spin adds to the “Trial multiplier” counter, which only resets when the trials end."),
                tr('كل ربح داخل التجارب يُضرب بالعدّاد كاملًا، لا بكرات تلك اللفة وحدها.', "Every win during trials is multiplied by the full counter, not just the orbs from that spin."),
              ]),

              _section(tr('حدود', "Limits"), [
                tr('الرهان من ${layout.minBet} إلى ${layout.maxBet} عملة.', "Bet from ${layout.minBet} to ${layout.maxBet} coins."),
                tr('أقصى ربح لجولة واحدة ${layout.maxWinMultiple}x من الرهان.', "The maximum win per round is ${layout.maxWinMultiple}x the bet."),
                tr('الجولة كاملة — التوزيع والتساقط والكرات والتجارب — تُحسم على الخادم قبل أن تتحرك أي صورة على شاشتك. الشاشة تعرض نتيجة مُقرَّرة، ولا تستطيع تغييرها.', "The entire round — deal, tumbles, orbs and trials — is decided on the server before anything moves on your screen. The screen displays a predetermined result and cannot change it."),
              ]),

              const SizedBox(height: 8),
              Text(
                tr('جدول الدفع', "Paytable"),
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                tr('القيم مضاعفات من إجمالي الرهان، حسب عدد الرموز الظاهرة.', "Values are multiples of the total bet, based on the number of symbols shown."),
                style: TextStyle(color: AsterionPalette.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _paytableHeader(),
              for (final id in kPayingSymbols)
                if (layout.paytable[id] != null) _paytableRow(id, layout.paytable[id]!),
              const SizedBox(height: 14),
              _specialRow(
                'CREST',
                tr('الشعار', "Crest"),
                tr('${layout.crestTrigger}+ في التوزيع الأول = ${layout.trialSpins} لفة مجانية', "${layout.crestTrigger}+ on the first board = ${layout.trialSpins} free spins"),
              ),
              _specialRow('ORB', tr('كرة العاصفة', "Storm orb"), tr('تُجمع قيمها وتضرب ربح الجولة', "Values are added and multiply the round win")),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AsterionPalette.amber.withValues(alpha: 0.10),
                  border: Border.all(color: AsterionPalette.amber.withValues(alpha: 0.45)),
                ),
                child: Text(
                  tr('العب للتسلية. الرصيد عملات داخل التطبيق، والنتائج عشوائية بالكامل — لا توجد طريقة '
                  'تزيد فرصك، ولا يمكن استرجاع رهان بعد تنفيذه.', "Play for fun. The balance is in-app coins, and results are entirely random. No method improves your chances, and bets cannot be refunded once placed."),
                  style: TextStyle(color: AsterionPalette.amberPale, fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<String> lines) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AsterionPalette.cyanPale,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 8),
                      child: Icon(Icons.circle, size: 5, color: AsterionPalette.cyan),
                    ),
                    Expanded(
                      child: Text(
                        line.replaceAll('**', ''),
                        style: const TextStyle(
                          color: Color(0xFFD6DEF0),
                          fontSize: 13.5,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _paytableHeader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 46),
            Expanded(child: SizedBox()),
            _HeadCell('8-9'),
            _HeadCell('10-11'),
            _HeadCell('12+'),
          ],
        ),
      );

  Widget _paytableRow(String id, List<double> values) {
    final info = kAsterionSymbols[id];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        children: [
          SymbolIcon(id, size: 38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              info?.name ?? id,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          for (final v in values)
            SizedBox(
              width: 52,
              child: Text(
                '${_fmt(v)}x',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AsterionPalette.amberPale,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _specialRow(String id, String name, String note) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AsterionPalette.cyan.withValues(alpha: 0.08),
          border: Border.all(color: AsterionPalette.cyan.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            SymbolIcon(id, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: const TextStyle(color: AsterionPalette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static String _fmt(double v) {
    if (v >= 10) return v.toStringAsFixed(0);
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        child: Text(
          label,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AsterionPalette.muted,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}
