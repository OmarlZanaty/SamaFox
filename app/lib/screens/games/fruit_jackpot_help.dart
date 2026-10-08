import 'package:flutter/material.dart';
import 'fruit_jackpot_engine.dart';
import 'fruit_jackpot_symbols.dart';

class FruitJackpotHelp extends StatelessWidget {
  final bool arabic;
  final Map<String, dynamic>? layout;
  const FruitJackpotHelp({super.key, required this.arabic, this.layout});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        arabic
            ? 'اختر الرهان ثم دوران. ٨ خطوط: ٣ صفوف و٣ أعمدة وقطران. ثلاثة رموز فاكهة متطابقة على الخط تدفع وفق الجدول × الرهان.'
            : 'Select a bet, then spin. Eight lines: three rows, three columns, two diagonals. Three matching fruit pay the table multiplier × bet.',
      ),
      for (final e in fruitJackpotPaytable.entries)
        ListTile(
          leading: SizedBox(
            width: 40,
            height: 40,
            child: fruitJackpotArt(e.key),
          ),
          title: Text('${e.key} ×${e.value}'),
        ),
      Text(
        arabic
            ? 'رقم الوسط (١ أو ٢ أو ٣ أو ٥ أو ٩) يضاعف كل أرباح الخطوط؛ الفاكهة خلفه تشارك في الخطوط. كل نافذة x2 تضاعف صفها الأفقي عندما تضيء.'
            : 'The centre number (1, 2, 3, 5 or 9) multiplies every line prize; the fruit behind it still counts. A lit x2 badge doubles its horizontal row.',
      ),
      Text(
        arabic
            ? 'رموز المكافأة لا تدفع على الخطوط. ثلاثة منها في الصف الأوسط تفتح جولة المكافأة: ×٢ أو ×٥ أو ×١٠ من الرهان، واختيار البطاقة يكشف الجائزة المحسوبة مسبقًا فقط. الجاكبوت: خط كرز ورقم الوسط ٩ — يدفع ×١٠٠٠ ثابتة بدل أرباح الخطوط.'
            : 'BONUS tokens never pay lines. Three of them across the middle row open the bonus round: 2×, 5× or 10× the bet; the card you pick only reveals the award already set. Jackpot: a cherry line while the centre shows 9 — pays a fixed 1000× instead of the line prizes.',
      ),
      Text(
        arabic
            ? 'كل خانة تُسحب مستقلة من الخادم. العائد النظري ٧٠٪ على المدى الطويل وليس ضمانًا لأي جلسة. الإيقاف ينهي الحركة فقط ولا يغير النتيجة.'
            : 'Every cell is drawn independently on the server. Theoretical return is 70% over the long run, not a promise for any session. STOP only ends the animation; it never changes the result.',
      ),
      Text(
        '${arabic ? 'حدود الرهان' : 'Bet limits'}: ${layout?['minBet'] ?? 100} – ${layout?['maxBet'] ?? 100000}\n${arabic ? 'حد الجولة' : 'Round cap'}: ${layout?['maxWinPerRound'] ?? '—'}\n${arabic ? 'حد اليوم' : 'Daily cap'}: ${layout?['dailyMaxWinPerUser'] ?? '—'}',
      ),
    ],
  );
}
