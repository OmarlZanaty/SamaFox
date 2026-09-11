import 'package:flutter/widgets.dart';

/// Every user-visible string in بوابات أوليمبوس, in Arabic and English.
///
/// Follows نيون فورتشن rather than the rest of the games, which hardcode
/// Arabic: this game's brief asked for true bilingual support with the layout
/// mirrored rather than just the words swapped, so the screen takes its
/// [textDirection] from here too.
///
/// The grid itself is deliberately *not* mirrored — a 6×5 pay-anywhere board
/// has no reading order, and flipping it would move Zeus off the right-hand
/// side where the whole composition puts him. Only the chrome flips.
///
/// Arabic is the default: anything not explicitly English gets it, matching the
/// app's own default locale.
class OlympusStrings {
  const OlympusStrings({required this.ar});

  final bool ar;

  static OlympusStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return OlympusStrings(ar: locale?.languageCode != 'en');
  }

  /// Chrome direction. The board keeps LTR regardless — see the class note.
  TextDirection get direction => ar ? TextDirection.rtl : TextDirection.ltr;

  // ── Identity ──────────────────────────────────────────────────────────────

  /// The game's name, in one place.
  ///
  /// "Gates of Olympus" is a Pragmatic Play trademark. Zeus, Mount Olympus and
  /// every mechanic in this game are free to use, but the *name* is not ours —
  /// change these two lines and the title moves everywhere it is shown.
  String get title => ar ? 'بوابات أوليمبوس' : 'Gates of Olympus';
  String get subtitle => ar ? 'غضب زيوس' : 'The Wrath of Zeus';

  // ── Chrome ────────────────────────────────────────────────────────────────
  String get back => ar ? 'رجوع' : 'Back';
  String get balance => ar ? 'الرصيد' : 'Balance';
  String get gems => ar ? 'الجواهر' : 'Gems';
  String get level => ar ? 'المستوى' : 'Level';

  /// Short form for the top-bar chip, where there is no room for the full word.
  String levelShort(int n) => ar ? 'مستوى $n' : 'Lv.$n';
  String get help => ar ? 'المساعدة' : 'Help';
  String get store => ar ? 'الباقات' : 'Store';
  String get settings => ar ? 'الإعدادات' : 'Settings';
  String get sound => ar ? 'الصوت' : 'Sound';
  String get fullscreen => ar ? 'ملء الشاشة' : 'Fullscreen';
  String get language => ar ? 'اللغة' : 'Language';
  String get close => ar ? 'إغلاق' : 'Close';
  String get loadFailed => ar ? 'تعذر تحميل اللعبة' : 'Could not load the game';
  String get spinFailed => ar ? 'تعذر تنفيذ الجولة' : 'Could not play the round';
  String get retry => ar ? 'إعادة المحاولة' : 'Try again';

  // ── Controls ──────────────────────────────────────────────────────────────
  String get spin => ar ? 'أدر' : 'SPIN';
  String get start => ar ? 'ابدأ' : 'START';
  String get stop => ar ? 'إيقاف' : 'STOP';
  String get auto => ar ? 'تلقائي' : 'AUTO';
  String get turbo => ar ? 'سريع' : 'TURBO';
  String get totalBet => ar ? 'إجمالي الرهان' : 'Total bet';
  String get totalWin => ar ? 'إجمالي الربح' : 'Total win';
  String get sequenceWin => ar ? 'ربح السلسلة' : 'Sequence win';
  String get multiplier => ar ? 'المضاعف' : 'Multiplier';
  String get increaseBet => ar ? 'زيادة الرهان' : 'Increase bet';
  String get decreaseBet => ar ? 'خفض الرهان' : 'Decrease bet';

  String get notEnoughCoins => ar ? 'رصيدك لا يكفي' : 'Not enough coins';
  String get autoStoppedLowBalance => ar
      ? 'تم إيقاف اللعب التلقائي — الرصيد غير كافٍ'
      : 'Autoplay stopped — not enough coins';
  String betRange(int min, int max) =>
      ar ? 'الرهان بين $min و $max عملة' : 'Bet between $min and $max coins';

  // ── Board ─────────────────────────────────────────────────────────────────
  String get tumbles => ar ? 'التساقطات' : 'Tumbles';
  String tumbleCount(int n) => ar ? 'التساقطات $n' : 'Tumbles $n';
  String symbolsMatched(int n) => ar ? '$n رموز' : '$n symbols';
  String get payAnywhere => ar ? 'الربح من أي مكان' : 'Pay anywhere';

  /// The one rule players most often get wrong, so it is stated in these words
  /// on the board, in the help sheet and in the bonus summary alike.
  String get multipliersAdd => ar
      ? 'المضاعفات تُجمع ولا تُضرب ببعضها'
      : 'Multipliers add together, they never multiply each other';

  String multiplierTotal(int n) => ar ? 'مضاعف ×$n' : '×$n multiplier';

  // ── Free spins ────────────────────────────────────────────────────────────
  String get freeSpins => ar ? 'اللفات المجانية' : 'Free spins';
  String get freeSpinsShort => ar ? 'مجانية' : 'Free';
  String freeSpinsLeft(int n) => ar ? 'متبقٍ $n' : '$n left';
  String freeSpinsAwarded(int n) => ar ? '$n لفة مجانية' : '$n free spins';
  String scattersLanded(int n) => ar ? '$n رموز زيوس' : '$n Zeus scatters';
  String retriggerAdded(int n) => ar ? '+$n لفات إضافية' : '+$n extra spins';
  String get bonusMeterNote => ar
      ? 'المضاعف لا يُصفَّر طوال الجولة المجانية'
      : 'The meter never resets while the bonus runs';
  String get bonusOver => ar ? 'انتهت اللفات المجانية' : 'Free spins finished';
  String get bonusTotal => ar ? 'إجمالي الجولة المجانية' : 'Free spins total';
  String get highestMultiplier => ar ? 'أعلى مضاعف' : 'Highest multiplier';
  String get spinsPlayed => ar ? 'اللفات الملعوبة' : 'Spins played';

  // ── Celebration tiers ─────────────────────────────────────────────────────
  String tier(String id) => switch (id) {
        'EPIC_WIN' => ar ? 'ربح أسطوري' : 'EPIC WIN',
        'MEGA_WIN' => ar ? 'ربح ضخم' : 'MEGA WIN',
        'BIG_WIN' => ar ? 'ربح كبير' : 'BIG WIN',
        'NICE_WIN' => ar ? 'ربح جميل' : 'NICE WIN',
        _ => id,
      };
  String get skip => ar ? 'تخطّي' : 'Skip';

  /// The word printed across the foot of the scatter tile. Short by necessity -
  /// it sits in a badge a few millimetres wide on a phone.
  String get scatterBadge => ar ? 'سكاتر' : 'SCATTER';

  // ── Help / paytable ───────────────────────────────────────────────────────
  String get rules => ar ? 'القواعد وجدول الأرباح' : 'Rules and paytable';
  String get howToWin => ar ? 'كيف تربح' : 'How you win';
  String howToWinBody(int minMatch) => ar
      ? 'اجمع $minMatch رموز متطابقة أو أكثر في أي مكان على الشبكة — '
          'المواضع لا تهم، العدد وحده هو ما يهم.'
      : 'Land $minMatch or more matching symbols anywhere on the grid — '
          'position never matters, only how many are showing.';
  String get tumbleRules => ar ? 'التساقط' : 'Tumbles';
  String get tumbleBody => ar
      ? 'الرموز الرابحة تختفي، وما فوقها يسقط مكانها، وتنزل رموز جديدة من الأعلى. '
          'يتكرر ذلك حتى تتوقف الجولة عن الربح.'
      : 'Winning symbols burst, everything above falls into the gaps, and new '
          'symbols drop in from the top. This repeats until nothing more wins.';
  String get multiplierRules => ar ? 'مضاعفات البرق' : 'Lightning multipliers';
  String multiplierBody(String values) => ar
      ? 'كرات زيوس الذهبية ($values) تسقط مع بقية الرموز ولا تُحسب ضمن أي تطابق. '
          'عند توقف التساقط تُجمع قيم كل الكرات الظاهرة في مضاعف واحد يُطبَّق على ربح السلسلة.'
      : "Zeus's golden orbs ($values) fall with everything else and never count "
          'toward a match. When the tumbles stop, every orb still showing is added '
          'into one multiplier and applied to the sequence win.';
  String get multiplierExample =>
      ar ? 'مثال: ٣× + ٥× + ٢٥× = ٣٣× — وليس ٣٧٥×' : 'Example: 3× + 5× + 25× = 33×, never 375×';
  String get freeSpinsRules => ar ? 'اللفات المجانية' : 'Free spins';
  String freeSpinsBody(int trigger, int spins, int retrigger, int extra) => ar
      ? '$trigger رموز زيوس أو أكثر في أي مكان تمنحك $spins لفة مجانية. '
          'داخل الجولة يتراكم المضاعف ولا يُصفَّر أبدًا، و$retrigger رموز أو أكثر '
          'تضيف $extra لفات.'
      : '$trigger or more Zeus scatters anywhere award $spins free spins. Inside '
          'the feature the multiplier meter accumulates and never resets, and '
          '$retrigger or more scatters add $extra more spins.';
  String get capRule => ar ? 'الحد الأقصى للجولة' : 'Round ceiling';
  String capBody(int multiple) => ar
      ? 'أقصى ربح لجولة واحدة هو $multiple ضعف الرهان.'
      : 'One round pays at most $multiple× the total bet.';
  String get cappedNotice => ar
      ? 'بلغت الجولة الحد الأقصى'
      : 'This round reached the ceiling';
  String get paytableTitle => ar ? 'جدول الأرباح' : 'Paytable';
  String get paytableNote => ar
      ? 'القيم مضاعفات لإجمالي الرهان.'
      : 'Values are multiples of the total bet.';
  String get band8 => ar ? '٨–٩' : '8–9';
  String get band10 => ar ? '١٠–١١' : '10–11';
  String get band12 => ar ? '١٢+' : '12+';

  // ── Symbol names ──────────────────────────────────────────────────────────
  String symbol(String id) => switch (id) {
        'GEM_BLUE' => ar ? 'الجوهرة الزرقاء' : 'Blue gem',
        'GEM_GREEN' => ar ? 'الجوهرة الخضراء' : 'Green gem',
        'GEM_YELLOW' => ar ? 'الجوهرة الصفراء' : 'Yellow gem',
        'GEM_PURPLE' => ar ? 'الجوهرة البنفسجية' : 'Purple gem',
        'GEM_RED' => ar ? 'الجوهرة الحمراء' : 'Red gem',
        'RING' => ar ? 'الخاتم' : 'Ring',
        'CHALICE' => ar ? 'الكأس' : 'Chalice',
        'HOURGLASS' => ar ? 'الساعة الرملية' : 'Hourglass',
        'CROWN' => ar ? 'التاج' : 'Crown',
        'SCATTER' => ar ? 'زيوس' : 'Zeus scatter',
        'MULT' => ar ? 'كرة البرق' : 'Lightning orb',
        _ => id,
      };

  // ── Fairness ──────────────────────────────────────────────────────────────
  String get fairness => ar ? 'العدالة المُثبتة' : 'Provably fair';
  String get fairnessBody => ar
      ? 'كل جولة تُحسم من بذرة الخادم وبذرتك ورقم الجولة. تُنشر بصمة بذرة الخادم '
          'قبل اللعب، فلا يمكن للخادم اختيارها بعد رؤية رهانك.'
      : 'Every round is decided from the server seed, your seed and the round '
          'number. The server seed hash is published before you play, so the '
          'server cannot pick a seed after seeing your bet.';
  String get serverSeedHash => ar ? 'بصمة بذرة الخادم' : 'Server seed hash';
  String get clientSeed => ar ? 'بذرتك' : 'Your seed';
  String get nonce => ar ? 'رقم الجولة' : 'Round number';
  String get saveSeed => ar ? 'حفظ' : 'Save';
  String get seedSaved => ar ? 'تم حفظ بذرتك' : 'Your seed is saved';
  String get rotateSeed => ar ? 'كشف وتدوير' : 'Reveal and rotate';
  String get revealedSeed => ar ? 'بذرة الخادم المكشوفة' : 'Revealed server seed';
  String get copied => ar ? 'تم النسخ' : 'Copied';

  // ── Settings ──────────────────────────────────────────────────────────────
  String get reducedMotion => ar ? 'تقليل الحركة' : 'Reduce motion';
  String get reducedMotionNote => ar
      ? 'يقصّر الحركات ويوقف الجسيمات.'
      : 'Shortens animations and stops the particles.';
  String get reducedFlash => ar ? 'تقليل الوميض' : 'Reduce flashing';
  String get reducedFlashNote => ar
      ? 'يوقف ومضات البرق الساطعة.'
      : 'Stops the bright lightning flashes.';
  String get highContrast => ar ? 'تباين عالٍ' : 'High contrast';
  String get highContrastNote => ar
      ? 'حدود أوضح للرموز على الخلفية.'
      : 'Stronger symbol borders against the background.';
  String get leftHanded => ar ? 'وضع اليد اليسرى' : 'Left-handed';
  String get leftHandedNote => ar
      ? 'ينقل زر الإدارة إلى الجهة الأخرى.'
      : 'Moves the spin button to the other side.';
  String get volume => ar ? 'مستوى الصوت' : 'Volume';

  // ── Responsible play ──────────────────────────────────────────────────────
  String get footer => ar
      ? 'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب.'
      : 'Runs on SamaFox coins — they do not convert to money and cannot be withdrawn.';
  String sessionReminder(int spins) => ar
      ? 'لعبت $spins جولة في هذه الجلسة'
      : "You've played $spins rounds this session";
  String get noStrategy => ar
      ? 'لا توجد طريقة لعب تضمن الربح — كل جولة مستقلة عن سابقتها.'
      : 'No way of playing guarantees a win — every round is independent of the last.';
}
