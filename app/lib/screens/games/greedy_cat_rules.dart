import 'package:flutter/material.dart';

import '../../repositories/greedy_cat_repository.dart';
import 'greedy_cat_art.dart';

/// «القواعد» — the rules and settings sheet.
///
/// Two jobs in one panel: teach the round, and hold the audio/motion switches.
/// The numbers are read off the layout the server sent rather than restated
/// here, so the sheet can never disagree with the table actually in play.
Future<void> showGreedyRules(
  BuildContext context, {
  required GreedyLayout? layout,
  required bool musicEnabled,
  required bool sfxEnabled,
  required bool reducedMotion,
  required ValueChanged<bool> onMusic,
  required ValueChanged<bool> onSfx,
  required ValueChanged<bool> onReducedMotion,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _RulesSheet(
      layout: layout,
      musicEnabled: musicEnabled,
      sfxEnabled: sfxEnabled,
      reducedMotion: reducedMotion,
      onMusic: onMusic,
      onSfx: onSfx,
      onReducedMotion: onReducedMotion,
    ),
  );
}

class _RulesSheet extends StatefulWidget {
  const _RulesSheet({
    required this.layout,
    required this.musicEnabled,
    required this.sfxEnabled,
    required this.reducedMotion,
    required this.onMusic,
    required this.onSfx,
    required this.onReducedMotion,
  });

  final GreedyLayout? layout;
  final bool musicEnabled;
  final bool sfxEnabled;
  final bool reducedMotion;
  final ValueChanged<bool> onMusic;
  final ValueChanged<bool> onSfx;
  final ValueChanged<bool> onReducedMotion;

  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  late bool _music = widget.musicEnabled;
  late bool _sfx = widget.sfxEnabled;
  late bool _reduced = widget.reducedMotion;

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final rtpPct = ((layout?.rtp ?? 0.9719) * 100).toStringAsFixed(2);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: GreedyPalette.cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: GreedyPalette.woodOutline, width: 3),
            ),
          ),
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                  children: [
                    _section('كيف تلعب', [
                      '١ — اختر قيمة الرهان من الشريط الأحمر.',
                      '٢ — اضغط على أي طبق لوضع الرهان عليه. يمكنك اللعب على أكثر من طبق في نفس الجولة.',
                      '٣ — اضغط الطبق مرة أخرى لإضافة رهان ثانٍ بنفس القيمة.',
                      '٤ — اضغط مطولاً على أي طبق لسحب قيمة رهان واحدة منه واستردادها.',
                      '٥ — زر «مسح» يسترجع كل رهانات الجولة، وزر «تكرار» يعيد رهان الجولة السابقة.',
                      '٦ — انتظر توقف العجلة تحت المؤشر في الأعلى.',
                    ]),
                    _multiplierTable(layout),
                    _section('رهان المجموعة', [
                      'زر «سلطة» يوزّع رهانك بالتساوي على الأطباق النباتية الأربعة، وزر «بيتزا» على أطباق اللحوم الأربعة.',
                      'رهان المجموعة ليس مضاعفة منفصلة: هو اختصار لوضع رُبع المبلغ على كل طبق، ثم يُحتسب كأربعة رهانات عادية.',
                      'لهذا يجب أن يقبل مبلغ رهان المجموعة القسمة على ٤.',
                    ]),
                    _section('مراحل الجولة', [
                      '«وقت الاختيار» — ٣٠ ثانية، الرهان مفتوح.',
                      '«النتيجة قادمة» — ٥ ثوانٍ، يُغلق الرهان وتستعد العجلة.',
                      '«وقت العرض» — تدور العجلة وتتوقف عند الطبق الفائز.',
                      'ثم تُعرض النتيجة، وتبدأ جولة جديدة تلقائيًا.',
                    ]),
                    _section('كيف يُحسب الربح', [
                      'العائد = ما راهنت به على الطبق الفائز × مضاعفة ذلك الطبق.',
                      'المضاعفة تشمل أصل الرهان: ١٠٠ على طبق ٥× تعيد ٥٠٠، منها ٤٠٠ ربح صافٍ.',
                      'الربح الصافي = العائد − مجموع كل ما راهنت به في الجولة.',
                      'أي رهان على طبق غير الفائز يخسر.',
                    ]),
                    _fairness(rtpPct, layout),
                    _section('ما معنى «ساخن»', [
                      'الشارة الساخنة تُوضع على الطبق الذي راهن عليه اللاعبون أكثر من غيره في هذه الجولة.',
                      'هي مؤشر اجتماعي فقط ولا تتنبأ بالنتيجة إطلاقًا — القرعة لا تنظر إلى أماكن الرهان.',
                    ]),
                    _settings(),
                    const SizedBox(height: 10),
                    _disclaimer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
        child: Row(
          children: [
            const CoinEmblem(size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'قواعد القط الجشع',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: GreedyPalette.darkText,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: GreedyPalette.woodOutline),
              tooltip: 'إغلاق',
            ),
          ],
        ),
      );

  Widget _section(String title, List<String> lines) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GreedyPalette.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GreedyPalette.warmPale, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: GreedyPalette.jackpotRed,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: GreedyPalette.darkText,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _multiplierTable(GreedyLayout? layout) {
    final symbols = layout?.symbols ?? const <GreedySymbol>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GreedyPalette.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GreedyPalette.warmPale, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الأطباق والمضاعفات',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: GreedyPalette.jackpotRed,
            ),
          ),
          const SizedBox(height: 10),
          if (symbols.isEmpty)
            const Text('جارٍ تحميل الطاولة…',
                style: TextStyle(color: GreedyPalette.mutedText))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in symbols)
                  Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: s.category == 'salad'
                          ? const Color(0xFFE7F7DF)
                          : const Color(0xFFFFE9DC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: GreedyPalette.woodOutline, width: 1.6),
                    ),
                    child: Column(
                      children: [
                        FoodIcon(s.key, size: 40),
                        const SizedBox(height: 2),
                        Text(
                          s.nameAr,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: GreedyPalette.darkText,
                          ),
                        ),
                        Text(
                          'مضاعفة ${s.multiplier}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: GreedyPalette.woodOutline,
                          ),
                        ),
                        Text(
                          'فرصة ${_chance(s, symbols)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: GreedyPalette.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _chance(GreedySymbol s, List<GreedySymbol> all) {
    final total = all.fold<int>(0, (sum, e) => sum + e.weight);
    if (total <= 0) return '—';
    return '${(s.weight / total * 100).toStringAsFixed(1)}%';
  }

  Widget _fairness(String rtpPct, GreedyLayout? layout) {
    final total = (layout?.symbols ?? const <GreedySymbol>[])
        .fold<int>(0, (sum, e) => sum + e.weight);
    return _section('النزاهة والاحتمالات', [
      'كل طبق له وزن ثابت في القرعة${total > 0 ? ' من مجموع $total' : ''}، والأوزان معكوسة مع المضاعفات.',
      'النتيجة يقرّرها الخادم وحده قبل أن تبدأ العجلة بالدوران، والتطبيق يعرض ما تقرّر فقط.',
      'قبل فتح الرهان يُنشر «بصمة» الجولة، وبعد ظهور النتيجة تُكشف بذرتها، فتستطيع إعادة حساب الطبق الفائز بنفسك.',
      'نسبة العائد النظرية $rtpPct٪، وهي متساوية على كل الأطباق: لا يوجد طبق «أفضل» من غيره على المدى الطويل.',
    ]);
  }

  Widget _settings() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GreedyPalette.warmPale,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GreedyPalette.woodOutline, width: 2),
        ),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الإعدادات',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: GreedyPalette.jackpotRed,
                ),
              ),
            ),
            _toggle('الموسيقى وصوت العجلة', _music, (v) {
              setState(() => _music = v);
              widget.onMusic(v);
            }),
            _toggle('المؤثرات الصوتية', _sfx, (v) {
              setState(() => _sfx = v);
              widget.onSfx(v);
            }),
            _toggle('تقليل الحركة', _reduced, (v) {
              setState(() => _reduced = v);
              widget.onReducedMotion(v);
            }, subtitle: 'يستبدل الدوران والقصاصات بانتقال هادئ'),
          ],
        ),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged,
          {String? subtitle}) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        activeColor: GreedyPalette.jackpotRed,
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: GreedyPalette.darkText,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(fontSize: 12, color: GreedyPalette.mutedText)),
      );

  Widget _disclaimer() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GreedyPalette.jackpotRed.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GreedyPalette.jackpotRed.withOpacity(0.4)),
        ),
        child: const Text(
          'شريط الكنز يعرض حجم النشاط على الطاولة فقط، وليس جائزة موعودة. '
          'العب بحدود ما تستطيع، ولا تعتمد على اللعبة كمصدر دخل.',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            fontWeight: FontWeight.w600,
            color: GreedyPalette.deepRed,
          ),
        ),
      );
}
