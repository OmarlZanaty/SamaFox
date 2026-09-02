import 'package:flutter/material.dart';

import '../../repositories/neon_fortune_repository.dart';
import 'neon_fortune_symbols.dart';

/// Paytable, feature rules, fairness and the honest money copy for نيون فورتشن.
///
/// The copy here says what the game actually does: it moves the same coins as
/// every other game in SamaFox. There is deliberately no "virtual points / no
/// monetary value" claim on top of a purchasable balance — see §0.1 of
/// docs/neon-fortune-design-review.md.
class NeonFortuneHelp extends StatelessWidget {
  const NeonFortuneHelp({super.key, required this.layout, required this.jackpots});

  final NeonLayout layout;
  final Map<String, int> jackpots;

  static Future<void> show(
    BuildContext context, {
    required NeonLayout layout,
    required Map<String, int> jackpots,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NeonFortuneHelp(layout: layout, jackpots: jackpots),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
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
              const _Title('نيون فورتشن — مدينة النمر'),
              const _Body(
                'خمس بكرات، ثلاثة صفوف، و20 خط دفع ثابت. الفوز يُحسب من البكرة '
                'الأولى إلى اليمين، وأعلى فوز على كل خط هو الذي يُحتسب.',
              ),
              const SizedBox(height: 18),
              const _Section('جدول الأرباح'),
              const _Body('القيم مضاعفات من إجمالي رهانك، لثلاثة وأربعة وخمسة رموز متطابقة.'),
              const SizedBox(height: 10),
              _paytable(),
              const SizedBox(height: 18),
              const _Section('الرموز الخاصة'),
              _rule('الرمز البديل', 'يحل محل كل الرموز العادية، ولا يحل محل رمز الانتشار أو رمز الجائزة. '
                  'داخل جولة اندفاع الأفق يحمل مضاعفًا ×2 أو ×3 مطبوعًا على وجهه.'),
              _rule('رمز الانتشار',
                  'لا يدفع بذاته. ${layout.scatterTrigger} رموز أو أكثر في أي مكان تفتح '
                  '${layout.freeSpinsAwarded} لفات مجانية.'),
              _rule('رمز الجائزة',
                  'يظهر على البكرات 1 و3 و5 فقط. ${layout.tokenTrigger} رموز تفتح خزنة الأضواء. '
                  'تكرار ظهوره لا يتغير مع حجم الرهان — الرهان الأكبر يكبّر الفوز، لا الفرصة.'),
              const SizedBox(height: 18),
              const _Section('اندفاع الأفق — اللفات المجانية'),
              _Body(
                '${layout.freeSpinsAwarded} لفات بنفس الرهان ودون خصم أي عملات. '
                'ظهور ${layout.scatterTrigger} رموز انتشار داخل الجولة يضيف '
                '${layout.freeSpinsRetrigger} لفات، بحد أقصى ${layout.freeSpinsCap} لفة للجولة كلها. '
                'في نهاية الجولة تظهر لوحة تجمع إجمالي الفوز وأكبر لفة.',
              ),
              const SizedBox(height: 18),
              const _Section('خزنة الأضواء'),
              _Body(
                '${layout.vaultCapsules} كبسولات، تفتحها واحدة تلو الأخرى. '
                'ثلاث كبسولات من نفس المستوى تمنحك جائزته التراكمية كاملة. '
                'إن لم تكتمل أي ثلاثية بعد كل الكبسولات، تحصل على جائزة مواساة '
                'قدرها ${layout.vaultConsolationMult}× رهانك — لا يوجد طريق مسدود.',
              ),
              const SizedBox(height: 18),
              const _Section('الجوائز التراكمية'),
              const _Body(
                'كل رهان يساهم بنسبة ثابتة في المستويات الأربعة. تُدفع الجائزة كاملة عند الفوز '
                'ثم تبدأ من جديد. القيم المعروضة حقيقية وتتحدث لحظيًا.',
              ),
              const SizedBox(height: 10),
              ...kJackpotTiers.map(_jackpotRow),
              const SizedBox(height: 18),
              const _Section('العدالة والأرقام'),
              const _Body(
                'كل لفة تُحسم على الخادم قبل أن تتحرك أي بكرة، عبر HMAC-SHA256 من بذرة الخادم '
                'وبذرة اللاعب ورقم اللفة — نفس نظام طيّار وبلينكو وأثيرفول. يمكنك تغيير بذرتك '
                'وكشف بذرة الخادم والتحقق من أي لفة سابقة.',
              ),
              const SizedBox(height: 8),
              const _Body(
                'نسبة العائد للاعب مقاسة على 600 ألف لفة: 97.03% على المدى الطويل '
                '(حافة البيت 2.97%)، منها 3.5% تذهب إلى الجوائز التراكمية. '
                'الرقم مقاس بمحاكاة مرفقة بالكود، وليس تقديرًا.',
              ),
              const SizedBox(height: 18),
              const _Section('عن العملات'),
              const _Body(
                'نيون فورتشن يستخدم عملات سمافوكس نفسها المستخدمة في بقية الألعاب والهدايا. '
                'العملات تُشحن أو تُربح داخل التطبيق، ولا تُحوَّل إلى نقود ولا تُسحب. '
                'العب للتسلية، وخذ استراحة متى شئت.',
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق', style: TextStyle(color: kNeonCyan, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paytable() {
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
          const Row(
            children: [
              SizedBox(width: 40),
              Expanded(child: Text('الرمز', style: TextStyle(color: kNeonTextDim, fontSize: 12))),
              _Head('×3'),
              _Head('×4'),
              _Head('×5'),
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
                      kNeonSymbolNames[id] ?? id,
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

  Widget _jackpotRow(String tier) {
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
              kJackpotNames[tier] ?? tier,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          if (rate != null)
            Text(
              '${(rate * 100).toStringAsFixed(2)}% من كل رهان',
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
