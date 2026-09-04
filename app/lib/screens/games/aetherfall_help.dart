import 'package:flutter/material.dart';

import '../../repositories/aetherfall_repository.dart';
import 'aetherfall_symbols.dart';

const _midnight = Color(0xFF0B1030);
const _cyan = Color(0xFF4DD8E6);
const _ember = Color(0xFFFF8A3D);
const _mint = Color(0xFF7CE8B0);

/// شرح اللعبة: القواعد وجدول الأرباح والميزات.
///
/// كل رقم هنا يأتي من [AetherfallLayout] الذي يرسله الخادم، لا من نص ثابت، حتى
/// يبقى الشرح مطابقًا للعبة الفعلية إذا تغيّرت أي قيمة.
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
              'كيف تلعب',
              style: TextStyle(color: _cyan, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _section(
              'ابدأ الجولة',
              'اختر قيمة رهانك ثم اضغط «اشعل». تمتلئ الخانات بالرموز، وكل فوز '
                  'يتلاشى تلقائيًا وتنزل رموز جديدة مكانه — لذلك قد تعطيك ضغطة '
                  'واحدة عدة تساقطات متتالية.',
            ),
            _section(
              'الفوز من أي مكان',
              'لا حاجة لأن تصطف الرموز أو تتلامس. يكفي أن يظهر ${layout.minMatch} '
                  'رموز متشابهة أو أكثر في أي مكان على اللوح (${layout.cols}×${layout.rows}) '
                  'حتى تربح. كلما زاد عددها زاد الربح.',
            ),
            const SizedBox(height: 18),
            const Text(
              'جدول الأرباح',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'الأرقام مضاعفات لقيمة رهانك، حسب عدد الرموز الظاهرة.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _paytable(),
            const SizedBox(height: 18),
            const Text(
              'الميزات',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _section(
              'المنشور البديل',
              'يحلّ محل أي رمز من الرموز الثمانية العادية ليكمل لك الفوز. لكنه لا '
                  'يحلّ محل مفتاح الخزنة.',
            ),
            _section(
              'مفتاح الخزنة وخزنة السماء',
              'ظهور ${layout.vaultKeyTrigger} مفاتيح أو أكثر في أول لوح من الجولة '
                  'يفتح خزنة السماء: ${layout.vaultBonusStartTumbles} تساقطات مجانية. '
                  'وداخل الخزنة، ${layout.vaultRetriggerKeys} مفاتيح في تساقط واحد '
                  'تضيف لك ${layout.vaultRetriggerTumbles} تساقطات أخرى.',
            ),
            _section(
              'شحنة الجمر',
              'كبسولات تحمل نسبة مئوية. تُحتسب فقط إذا وقع فوز في نفس التساقط. في '
                  'اللعب العادي تُجمع كل الشحنات خلال السلسلة وتُضاف مرة واحدة إلى ربح '
                  'السلسلة، وفي خزنة السماء تتجمع في «بنك الشحن» وتُضاف مرة واحدة إلى '
                  'إجمالي الخزنة في النهاية.',
            ),
            _section(
              'قفل الكوكبة',
              'داخل خزنة السماء فقط. كل تساقط رابح يثبّت رمزًا واحدًا في مكانه بخيط '
                  'كوكبة: يبقى الرمز ثابتًا بينما يتساقط ما حوله، ويستمر إلى التساقط '
                  'التالي. الرمز المثبّت يمكن أن يربح، وعندها يُفك تثبيته. وعند تثبيت '
                  '${layout.constellationLockTarget} رموز تتصل الخيوط وتحصل على «تساقط '
                  'نجمي» مجاني مع منشور بديل مضمون.',
            ),
            const SizedBox(height: 18),
            const Text(
              'التحكم والإعدادات',
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _section(
              'اللعب التلقائي',
              'يكرّر «اشعل» بنفس الرهان ويخصم العملات في كل مرة. اضغط «إيقاف» لتتوقف '
                  'فورًا، وهو يتوقف من نفسه إذا لم يعد رصيدك يغطي الرهان.',
            ),
            _section(
              'الصوت والحركة وسهولة القراءة',
              'في الإعدادات: مستوى الصوت، و«حركة أقل» لتقصير الحركات وإلغاء الاهتزاز '
                  'والوميض، و«تباين عالٍ»، و«علامات الرموز» التي تضع على كل رمز علامته '
                  'الخاصة فلا يبقى اللون هو الفارق الوحيد، وتحكّم لليد اليسرى.',
            ),
            _section(
              'عدالة مثبتة',
              'من الإعدادات أيضًا تفتح صفحة العدالة: بصمة بذرة الخادم وبذرتك ورقم '
                  'الجولة. تستطيع تغيير بذرتك في أي وقت.',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _ember.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _ember.withValues(alpha: 0.4)),
              ),
              child: Text(
                'أثيرفول تُلعب بعملاتك. كل ضغطة «اشعل» تخصم رهانك '
                '(${layout.minBet}–${layout.maxBet} عملة) قبل حساب النتيجة، وأي ربح '
                'يُضاف إلى رصيدك مباشرة. كل جولة — بما فيها خزنة السماء كاملة — '
                'يحسمها الخادم من بذرتين يمكنك التحقق منهما، فلا شيء في التطبيق على '
                'جهازك يؤثر على النتيجة.',
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6),
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
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.7)),
          ],
        ),
      );

  /// الأرباح تأتي من جدول الخادم، وقد تحمل خانتين عشريتين (0.95) أو لا شيء (135).
  /// التقريب إلى خانة واحدة كان سيعرض x0.9 لرمز يدفع فعليًا 0.95.
  static String _payout(num v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  Widget _paytable() {
    final symbols = layout.standardSymbols;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: SizedBox()),
              _BandLabel('9-11'),
              _BandLabel('12-14'),
              _BandLabel('15+'),
            ],
          ),
        ),
        for (final sym in symbols)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    kSymbolNames[sym] ?? sym,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                for (final v in layout.paytable[sym] ?? const [0, 0, 0])
                  Container(
                    width: 52,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_payout(v)}x',
                      style: const TextStyle(color: _cyan, fontSize: 11),
                    ),
                  ),
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
        width: 52,
        margin: const EdgeInsets.only(right: 6),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      );
}

/// شرح قصير يظهر مرة واحدة قبل أول جولة.
///
/// اللوح لا يشبه ماكينات الحظ المعتادة — لا خطوط ولا اصطفاف — ولو دخل اللاعب
/// دون تفسير فلن يفهم لماذا ربح. أربع نقاط فقط، ثم زر واحد يبدأ اللعب، وبقية
/// التفاصيل تبقى في صفحة «كيف تلعب».
class AetherfallFirstRunSheet extends StatelessWidget {
  const AetherfallFirstRunSheet({
    super.key,
    required this.layout,
    required this.onOpenHelp,
  });

  final AetherfallLayout layout;
  final VoidCallback onOpenHelp;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 18),
            const Text(
              'أثيرفول في أربع نقاط',
              style: TextStyle(color: _cyan, fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _point(
              Icons.grid_view_rounded,
              _cyan,
              'الفوز من أي مكان',
              '${layout.minMatch} رموز متشابهة أو أكثر في أي مكان على اللوح — '
                  'لا يلزم أن تصطف أو تتلامس.',
            ),
            _point(
              Icons.south_rounded,
              _mint,
              'الرموز تتساقط',
              'الرموز الرابحة تختفي وتنزل غيرها مكانها، فقد تربح عدة مرات من ضغطة واحدة.',
            ),
            _point(
              Icons.bolt_rounded,
              _ember,
              'شحنة الجمر تزيد الربح',
              'كبسولات بنسبة مئوية تُجمع خلال الجولة وتُضاف دفعة واحدة إلى ربح السلسلة.',
            ),
            _point(
              Icons.vpn_key_rounded,
              const Color(0xFFCB9B5C),
              'المفاتيح تفتح الخزنة',
              '${layout.vaultKeyTrigger} مفاتيح في أول لوح تفتح خزنة السماء: '
                  '${layout.vaultBonusStartTumbles} تساقطات مجانية.',
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cyan,
                      foregroundColor: const Color(0xFF07030F),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'ابدأ اللعب',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenHelp();
                  },
                  child: const Text('الشرح الكامل', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(IconData icon, Color color, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.16),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
