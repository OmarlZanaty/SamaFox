import 'package:flutter/widgets.dart';

/// Every user-visible string in نيون فورتشن, in Arabic and English.
///
/// The rest of the games in this app hardcode Arabic. This one carries both,
/// because the design brief asked for true bilingual support with the layout
/// mirrored rather than just the words swapped — so the screen also takes its
/// [textDirection] from here instead of pinning itself to RTL.
///
/// Arabic is the default: anything that is not explicitly English gets it, which
/// matches the app's own default locale.
class NeonStrings {
  const NeonStrings({required this.ar});

  final bool ar;

  static NeonStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return NeonStrings(ar: locale?.languageCode != 'en');
  }

  TextDirection get direction => ar ? TextDirection.rtl : TextDirection.ltr;

  // ── Cabinet chrome ────────────────────────────────────────────────────────
  String get title => ar ? 'نيون فورتشن' : 'Neon Fortune';
  String get fullTitle => ar ? 'نيون فورتشن — مدينة النمر' : 'Neon Fortune: Tiger City';
  String get back => ar ? 'رجوع' : 'Back';
  String get sound => ar ? 'الصوت' : 'Sound';
  String get reducedMotion => ar ? 'تقليل الحركة' : 'Reduce motion';
  String get rules => ar ? 'القواعد وجدول الأرباح' : 'Rules and paytable';
  String get loadFailed => ar ? 'تعذر تحميل اللعبة' : 'Could not load the game';
  String get retry => ar ? 'إعادة المحاولة' : 'Try again';
  String get footer => ar
      ? 'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب.'
      : 'Runs on SamaFox coins — they do not convert to money and cannot be withdrawn.';

  // ── Controls ──────────────────────────────────────────────────────────────
  String get spin => ar ? 'أدر' : 'SPIN';
  String get bet => ar ? 'الرهان' : 'Bet';
  String get lastWin => ar ? 'آخر فوز' : 'Last win';
  String get autoStoppedLowBalance => ar
      ? 'توقف التشغيل التلقائي — الرصيد غير كافٍ'
      : 'Autoplay stopped — not enough coins';

  String line(int n) => ar ? 'خط $n' : 'Line $n';
  String lineWin(int n, String amount) => ar ? 'خط $n · $amount' : 'Line $n · $amount';
  String winningLines(int n) => ar ? '$n خطوط رابحة' : '$n winning lines';
  String extraSpins(int n) => ar ? '+$n لفات إضافية' : '+$n extra spins';

  // ── Low balance ───────────────────────────────────────────────────────────
  String get lowBalanceTitle => ar ? 'الرصيد لا يكفي' : 'Not enough coins';
  String get lowBalanceBody => ar
      ? 'اختر رهانًا أقل، أو افتح صندوق الحظ عندما يجهز.'
      : 'Pick a smaller bet, or open the Lucky Drop when it is ready.';
  String get lowerBet => ar ? 'خفض الرهان' : 'Lower the bet';
  String get ok => ar ? 'حسنًا' : 'OK';

  // ── Lucky Drop ────────────────────────────────────────────────────────────
  String get luckyDrop => ar ? 'صندوق الحظ' : 'Lucky Drop';
  String get luckyReady => ar ? 'جاهز' : 'Ready';
  String luckyClaimed(String amount) => ar ? 'حصلت على $amount عملة' : 'Collected $amount coins';
  String luckyIn(String time) => ar ? 'بعد $time' : 'in $time';
  String get luckyNotReady => ar ? 'الصندوق لم يجهز بعد' : 'The drop is not ready yet';

  /// Compact cooldown, e.g. "٣س ٢٠د" / "3h 20m".
  String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return ar ? '$h س $m د' : '${h}h ${m}m';
    final s = d.inSeconds.remainder(60);
    return ar ? '$m د $s ث' : '${m}m ${s}s';
  }

  // ── Feed ──────────────────────────────────────────────────────────────────
  String get feedEmpty => ar
      ? 'أكبر الأرباح تظهر هنا فور حدوثها'
      : 'The biggest wins show up here as they happen';

  // ── Skyline Rush ──────────────────────────────────────────────────────────
  String get rushName => ar ? 'اندفاع الأفق' : 'Skyline Rush';
  String rushCounter(int left, int total) =>
      ar ? 'اندفاع الأفق $left/$total' : 'Skyline Rush $left/$total';
  String rushFreeSpins(int n) => ar ? '$n لفات مجانية' : '$n Free Spins';
  String get rushSubtitle => ar
      ? 'اندفاع الأفق — نفس الرهان، بلا خصم'
      : 'Skyline Rush — same bet, nothing deducted';
  String get skip => ar ? 'تخطي' : 'Skip';
  String get spinsPlayed => ar ? 'عدد اللفات' : 'Spins played';
  String get bestSpin => ar ? 'أكبر لفة' : 'Best single spin';
  String get roundTotal => ar ? 'إجمالي الجولة' : 'Round total';
  String get carryOn => ar ? 'متابعة' : 'Continue';

  // ── Vault of Lights ───────────────────────────────────────────────────────
  String get vaultName => ar ? 'خزنة الأضواء' : 'Vault of Lights';
  String get vaultInstructions => ar
      ? 'اكشف الكبسولات — ثلاث متطابقة تفوز بالجائزة'
      : 'Open the capsules — three of a kind wins that jackpot';
  String get vaultWon => ar ? 'ثلاثية مكتملة!' : 'Three of a kind!';
  String get vaultMissed => ar
      ? 'لم تكتمل ثلاثية — جائزة مواساة'
      : 'No trio — consolation prize';
  String get consolation => ar ? 'جائزة مواساة' : 'Consolation';
  String remaining(int n) => ar ? 'المتبقي: $n' : 'Left: $n';
  String get revealAll => ar ? 'اكشف الكل' : 'Reveal all';
  String coins(String amount) => ar ? '$amount عملة' : '$amount coins';

  // ── Celebrations ──────────────────────────────────────────────────────────
  String celebration(String tier) => switch (tier) {
        'CITY_LIGHTS' => ar ? 'أضواء المدينة' : 'CITY LIGHTS',
        'MEGA_WIN' => ar ? 'فوز ضخم' : 'MEGA WIN',
        'BIG_WIN' => ar ? 'فوز كبير' : 'BIG WIN',
        _ => ar ? 'فوز' : 'WIN',
      };

  // ── Symbols and tiers ─────────────────────────────────────────────────────
  String symbol(String id) => switch (id) {
        'TIGER' => ar ? 'حارس النمر' : 'Tiger Guardian',
        'PANTHER' => ar ? 'الفهد البلوري' : 'Crystal Panther',
        'CRANE' => ar ? 'كركي الحظ' : 'Fortune Crane',
        'KOI' => ar ? 'سمكة النيون' : 'Neon Koi',
        'LANTERN' => ar ? 'فانوس الحظ' : 'Lucky Lantern',
        'COIN' => ar ? 'عملة النجمة' : 'Star Coin',
        'WILD' => ar ? 'الرمز البديل' : 'Wild',
        'SCATTER' => ar ? 'رمز الانتشار' : 'Scatter',
        'TOKEN' => ar ? 'رمز الجائزة' : 'Jackpot Token',
        _ => id,
      };

  String tier(String id) => switch (id) {
        'SPARK' => ar ? 'شرارة' : 'Spark',
        'GLOW' => ar ? 'وهج' : 'Glow',
        'BEACON' => ar ? 'منارة' : 'Beacon',
        'CITY' => ar ? 'مدينة' : 'City',
        _ => id,
      };

  // ── Help sheet ────────────────────────────────────────────────────────────
  String get helpIntro => ar
      ? 'خمس بكرات، ثلاثة صفوف، و20 خط دفع ثابت. الفوز يُحسب من البكرة الأولى إلى '
          'اليمين، وأعلى فوز على كل خط هو الذي يُحتسب.'
      : 'Five reels, three rows, 20 fixed paylines. Wins are counted from reel one '
          'left to right, and only the highest win on each line counts.';

  String get paytableHeading => ar ? 'جدول الأرباح' : 'Paytable';
  String get paytableNote => ar
      ? 'القيم مضاعفات من إجمالي رهانك، لثلاثة وأربعة وخمسة رموز متطابقة.'
      : 'Values are multiples of your total bet, for three, four and five matching symbols.';
  String get symbolColumn => ar ? 'الرمز' : 'Symbol';

  String get specialsHeading => ar ? 'الرموز الخاصة' : 'Special symbols';
  String get wildRule => ar
      ? 'يحل محل كل الرموز العادية، ولا يحل محل رمز الانتشار أو رمز الجائزة. داخل '
          'جولة اندفاع الأفق يحمل مضاعفًا ×2 أو ×3 مطبوعًا على وجهه.'
      : 'Substitutes for every regular symbol, but never for the scatter or the '
          'jackpot token. Inside Skyline Rush it carries a ×2 or ×3 multiplier printed on its face.';
  String scatterRule(int trigger, int spins) => ar
      ? 'لا يدفع بذاته. $trigger رموز أو أكثر في أي مكان تفتح $spins لفات مجانية.'
      : 'Pays nothing on its own. $trigger or more anywhere opens $spins free spins.';
  String tokenRule(int trigger) => ar
      ? 'يظهر على البكرات 1 و3 و5 فقط. $trigger رموز تفتح خزنة الأضواء. تكرار ظهوره لا '
          'يتغير مع حجم الرهان — الرهان الأكبر يكبّر الفوز، لا الفرصة.'
      : 'Lands on reels 1, 3 and 5 only. $trigger of them open the Vault of Lights. '
          'How often it appears does not change with your bet — a bigger bet grows the win, never the odds.';

  String rushRules(int spins, int trigger, int retrigger, int cap) => ar
      ? '$spins لفات بنفس الرهان ودون خصم أي عملات. ظهور $trigger رموز انتشار داخل '
          'الجولة يضيف $retrigger لفات، بحد أقصى $cap لفة للجولة كلها. في نهاية الجولة '
          'تظهر لوحة تجمع إجمالي الفوز وأكبر لفة.'
      : '$spins spins at the same bet with nothing deducted. $trigger scatters inside '
          'the round add $retrigger more spins, up to $cap for the whole round. A summary '
          'panel at the end totals the round and its best spin.';

  String vaultRules(int capsules, int mult) => ar
      ? '$capsules كبسولات، تفتحها واحدة تلو الأخرى. ثلاث كبسولات من نفس المستوى تمنحك '
          'جائزته التراكمية كاملة. إن لم تكتمل أي ثلاثية بعد كل الكبسولات، تحصل على جائزة '
          'مواساة قدرها $mult× رهانك — لا يوجد طريق مسدود.'
      : '$capsules capsules, opened one at a time. Three of the same tier award that '
          'jackpot in full. If no trio completes after every capsule, you get a '
          'consolation of $mult× your bet — there is no dead end.';

  String get jackpotsHeading => ar ? 'الجوائز التراكمية' : 'Progressive jackpots';
  String get jackpotsNote => ar
      ? 'كل رهان يساهم بنسبة ثابتة في المستويات الأربعة. تُدفع الجائزة كاملة عند الفوز ثم '
          'تبدأ من جديد. القيم المعروضة حقيقية وتتحدث لحظيًا.'
      : 'Every bet contributes a fixed share to the four tiers. A jackpot pays out in '
          'full and then starts again. The values shown are real and update live.';
  String contributionOf(String percent) =>
      ar ? '$percent% من كل رهان' : '$percent% of every bet';

  String get fairnessHeading => ar ? 'العدالة والأرقام' : 'Fairness and the numbers';
  String get fairnessBody => ar
      ? 'كل لفة تُحسم على الخادم قبل أن تتحرك أي بكرة، عبر HMAC-SHA256 من بذرة الخادم '
          'وبذرة اللاعب ورقم اللفة — نفس نظام طيّار وبلينكو وأثيرفول. يمكنك تغيير بذرتك '
          'وكشف بذرة الخادم والتحقق من أي لفة سابقة.'
      : 'Every spin is settled on the server before a reel moves, from HMAC-SHA256 over '
          'the server seed, your seed and the spin number — the same scheme as Crash, '
          'Plinko and Aetherfall. You can change your seed, reveal the server seed and '
          'verify any past spin.';
  String get rtpBody => ar
      ? 'نسبة العائد للاعب مقاسة على 600 ألف لفة: 97.03% على المدى الطويل (حافة البيت '
          '2.97%)، منها 3.5% تذهب إلى الجوائز التراكمية. الرقم مقاس بمحاكاة مرفقة بالكود، '
          'وليس تقديرًا.'
      : 'Return to player, measured over 1.2 million spins: 97.06% long-run (house edge '
          '2.94%), of which 3.5% goes to the progressive jackpots. That figure is measured '
          'by a simulator committed alongside the code, not estimated.';

  String get coinsHeading => ar ? 'عن العملات' : 'About the coins';
  String get coinsBody => ar
      ? 'نيون فورتشن يستخدم عملات سمافوكس نفسها المستخدمة في بقية الألعاب والهدايا. '
          'العملات تُشحن أو تُربح داخل التطبيق، ولا تُحوَّل إلى نقود ولا تُسحب. العب '
          'للتسلية، وخذ استراحة متى شئت.'
      : 'Neon Fortune uses the same SamaFox coins as the other games and gifts. Coins are '
          'topped up or won inside the app; they do not convert to money and cannot be '
          'withdrawn. Play for fun, and take a break whenever you like.';

  String luckyDropRules(String amount, String cooldown) => ar
      ? 'صندوق الحظ يمنحك $amount عملة مجانًا كل $cooldown، بلا شراء وبلا إعلانات.'
      : 'The Lucky Drop gives you $amount free coins every $cooldown — no purchase, no ads.';

  String get close => ar ? 'إغلاق' : 'Close';
}
