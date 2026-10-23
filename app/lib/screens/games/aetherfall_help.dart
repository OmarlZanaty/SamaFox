import '../../l10n/tr.dart';
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
            Text(
              tr('كيف تلعب', "How to play"),
              style: TextStyle(color: _cyan, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _section(
              tr('ابدأ الجولة', "Start a round"),
              tr('اختر قيمة رهانك ثم اضغط «اشعل». تمتلئ الخانات بالرموز، وكل فوز '
                  'يتلاشى تلقائيًا وتنزل رموز جديدة مكانه — لذلك قد تعطيك ضغطة '
                  'واحدة عدة تساقطات متتالية.', "Choose your bet, then tap “Ignite”. Symbols fill the board; winning symbols disappear and new ones drop into place, so one tap can trigger several tumbles."),
            ),
            _section(
              tr('الفوز من أي مكان', "Win anywhere"),
              tr('لا حاجة لأن تصطف الرموز أو تتلامس. يكفي أن يظهر ${layout.minMatch} '
                  'رموز متشابهة أو أكثر في أي مكان على اللوح (${layout.cols}×${layout.rows}) '
                  'حتى تربح. كلما زاد عددها زاد الربح.', "Symbols do not need to line up or touch. ${layout.minMatch} or more matching symbols anywhere on the board (${layout.cols}×${layout.rows}) win. More symbols mean a bigger win."),
            ),
            const SizedBox(height: 18),
            Text(
              tr('جدول الأرباح', "Paytable"),
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              tr('الأرقام مضاعفات لقيمة رهانك، حسب عدد الرموز الظاهرة.', "Numbers are multipliers of your bet, based on how many symbols appear."),
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _paytable(),
            const SizedBox(height: 18),
            Text(
              tr('الميزات', "Features"),
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _section(
              tr('المنشور البديل', "Wild prism"),
              tr('يحلّ محل أي رمز من الرموز الثمانية العادية ليكمل لك الفوز. لكنه لا '
                  'يحلّ محل مفتاح الخزنة.', "Replaces any of the eight regular symbols to complete a win, but cannot replace a vault key."),
            ),
            _section(
              tr('مفتاح الخزنة وخزنة السماء', "Vault key and Sky Vault"),
              tr('ظهور ${layout.vaultKeyTrigger} مفاتيح أو أكثر في أول لوح من الجولة '
                  'يفتح خزنة السماء: ${layout.vaultBonusStartTumbles} تساقطات مجانية. '
                  'وداخل الخزنة، ${layout.vaultRetriggerKeys} مفاتيح في تساقط واحد '
                  'تضيف لك ${layout.vaultRetriggerTumbles} تساقطات أخرى.', "${layout.vaultKeyTrigger} or more keys on the first board open the Sky Vault: ${layout.vaultBonusStartTumbles} free tumbles. Inside the vault, ${layout.vaultRetriggerKeys} keys in one tumble add ${layout.vaultRetriggerTumbles} more tumbles."),
            ),
            _section(
              tr('شحنة الجمر', "Ember charge"),
              tr('كبسولات تحمل نسبة مئوية. تُحتسب فقط إذا وقع فوز في نفس التساقط. في '
                  'اللعب العادي تُجمع كل الشحنات خلال السلسلة وتُضاف مرة واحدة إلى ربح '
                  'السلسلة، وفي خزنة السماء تتجمع في «بنك الشحن» وتُضاف مرة واحدة إلى '
                  'إجمالي الخزنة في النهاية.', "Capsules carrying a percentage count only when the same tumble wins. In regular play, all charges in the sequence are added once to the sequence win. In the Sky Vault, they build up in the Charge Bank and are added once to the vault total at the end."),
            ),
            _section(
              tr('قفل الكوكبة', "Constellation lock"),
              tr('داخل خزنة السماء فقط. كل تساقط رابح يثبّت رمزًا واحدًا في مكانه بخيط '
                  'كوكبة: يبقى الرمز ثابتًا بينما يتساقط ما حوله، ويستمر إلى التساقط '
                  'التالي. الرمز المثبّت يمكن أن يربح، وعندها يُفك تثبيته. وعند تثبيت '
                  '${layout.constellationLockTarget} رموز تتصل الخيوط وتحصل على «تساقط '
                  'نجمي» مجاني مع منشور بديل مضمون.', "Only inside the Sky Vault. Each winning tumble locks one symbol with a constellation thread. It stays in place while others tumble, through the next tumble. A locked symbol can win, which unlocks it. Locking ${layout.constellationLockTarget} symbols connects the threads and grants a free “Star Tumble” with a guaranteed wild prism."),
            ),
            const SizedBox(height: 18),
            Text(
              tr('التحكم والإعدادات', "Controls and settings"),
              style: TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _section(
              tr('اللعب التلقائي', "Autoplay"),
              tr('يكرّر «اشعل» بنفس الرهان ويخصم العملات في كل مرة. اضغط «إيقاف» لتتوقف '
                  'فورًا، وهو يتوقف من نفسه إذا لم يعد رصيدك يغطي الرهان.', "Repeats “Ignite” with the same bet, deducting coins each time. Tap “Stop” to stop immediately. It also stops when your balance cannot cover the bet."),
            ),
            _section(
              tr('الصوت والحركة وسهولة القراءة', "Sound, motion and readability"),
              tr('في الإعدادات: مستوى الصوت، و«حركة أقل» لتقصير الحركات وإلغاء الاهتزاز '
                  'والوميض، و«تباين عالٍ»، و«علامات الرموز» التي تضع على كل رمز علامته '
                  'الخاصة فلا يبقى اللون هو الفارق الوحيد، وتحكّم لليد اليسرى.', "Settings include volume, “Reduced motion” to shorten animations and disable vibration and flashing, “High contrast”, “Symbol labels” to distinguish symbols beyond color, and left-handed controls."),
            ),
            _section(
              tr('عدالة مثبتة', "Provably fair"),
              tr('من الإعدادات أيضًا تفتح صفحة العدالة: بصمة بذرة الخادم وبذرتك ورقم '
                  'الجولة. تستطيع تغيير بذرتك في أي وقت.', "Open the fairness page from settings to see the server seed hash, your seed and the round number. You can change your seed at any time."),
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
                tr('أثيرفول تُلعب بعملاتك. كل ضغطة «اشعل» تخصم رهانك '
                '(${layout.minBet}–${layout.maxBet} عملة) قبل حساب النتيجة، وأي ربح '
                'يُضاف إلى رصيدك مباشرة. كل جولة — بما فيها خزنة السماء كاملة — '
                'يحسمها الخادم من بذرتين يمكنك التحقق منهما، فلا شيء في التطبيق على '
                'جهازك يؤثر على النتيجة.', "Aetherfall uses your coins. Each tap of “Ignite” deducts your bet (${layout.minBet}–${layout.maxBet} coins) before calculating the result. Wins go straight to your balance. Each round, including the entire Sky Vault, is decided by the server using two verifiable seeds. Nothing in the app on your device affects the result."),
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
            Text(
              tr('أثيرفول في أربع نقاط', "Aetherfall in four points"),
              style: TextStyle(color: _cyan, fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _point(
              Icons.grid_view_rounded,
              _cyan,
              tr('الفوز من أي مكان', "Win anywhere"),
              tr('${layout.minMatch} رموز متشابهة أو أكثر في أي مكان على اللوح — '
                  'لا يلزم أن تصطف أو تتلامس.', "${layout.minMatch} or more matching symbols anywhere on the board — no need to line up or touch."),
            ),
            _point(
              Icons.south_rounded,
              _mint,
              tr('الرموز تتساقط', "Symbols tumble"),
              tr('الرموز الرابحة تختفي وتنزل غيرها مكانها، فقد تربح عدة مرات من ضغطة واحدة.', "Winning symbols disappear and new ones drop in, so you can win several times from a single tap."),
            ),
            _point(
              Icons.bolt_rounded,
              _ember,
              tr('شحنة الجمر تزيد الربح', "Ember charges boost wins"),
              tr('كبسولات بنسبة مئوية تُجمع خلال الجولة وتُضاف دفعة واحدة إلى ربح السلسلة.', "Percentage capsules collect during the round and are added once to the sequence win."),
            ),
            _point(
              Icons.vpn_key_rounded,
              const Color(0xFFCB9B5C),
              tr('المفاتيح تفتح الخزنة', "Keys open the vault"),
              tr('${layout.vaultKeyTrigger} مفاتيح في أول لوح تفتح خزنة السماء: '
                  '${layout.vaultBonusStartTumbles} تساقطات مجانية.', "${layout.vaultKeyTrigger} keys on the first board open the Sky Vault: ${layout.vaultBonusStartTumbles} free tumbles."),
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
                    child: Text(
                      tr('ابدأ اللعب', "Start playing"),
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
                  child: Text(tr('الشرح الكامل', "Full guide"), style: TextStyle(color: Colors.white54)),
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
