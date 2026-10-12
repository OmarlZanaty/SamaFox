import 'car_wheel_engine.dart';

class CarWheelStrings {
  final bool ar;
  const CarWheelStrings(this.ar);
  String text(String key) => (ar ? _arabic : _english)[key] ?? key;
  String get footer => ar
      ? 'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب، ولا توجد جوائز مالية حقيقية.'
      : 'Runs on SamaFox coins — they do not convert to money or withdraw; no real-money prizes.';
  String round(int n) => ar ? 'اللعبة $n' : 'Game $n';
  String seconds(int s) => ar ? '$s ث' : '${s}s';
  String winning(String key) {
    final b = carWheelBet(key)!;
    return ar
        ? '${b.name} فاز — x${b.multiplier}'
        : '${b.name} won — x${b.multiplier}';
  }

  String bet(String key) => carWheelBet(key)?.name ?? key;
  String betLabel(CarWheelSegment b) => ar
      ? 'راهن على ${b.name} بمضاعف ${b.multiplier}'
      : 'Bet on ${b.name} at ${b.multiplier}x';
  String error(String code) => text(code) == code ? text('FAILED') : text(code);

  static const _english = {
    'mineAll': 'Mine / All',
    'title': 'CAR WHEEL',
    'ranking': 'Ranking',
    'players': 'Players',
    'totalBet': 'Total Bet',
    'myTotalBet': 'My total bet',
    'balance': 'Balance',
    'help': 'Help',
    'paytable': 'Paytable',
    'history': 'History',
    'settings': 'Settings',
    'sound': 'Sound',
    'motion': 'Motion',
    'language': 'Language',
    'arabic': 'العربية',
    'english': 'English',
    'close': 'Close',
    'back': 'Back',
    'retry': 'Try again',
    'loading': 'Loading table…',
    'clear': 'Clear',
    'undo': 'Undo',
    'rebet': 'Rebet',
    'betting': 'Place your bets',
    'closing': 'Bets closed — wait for the result',
    'spinning': 'Spinning…',
    'result': 'Result',
    'youWon': 'You won',
    'noWin': 'No win this round',
    'payout': 'Pays (bet included)',
    'emptyHistory': 'No rounds yet.',
    'emptyRanking': 'No winners yet today — be the first!',
    'emptyPlayers': 'No bets on the table yet this round.',
    'todayNet': 'Your net today',
    'bestWin': 'Best win today',
    'statsNote': 'Past results do not predict the next round.',
    'lastResults': 'Last results',
    'rules':
        'One shared table. Pick a chip, then tap a brand before the 25-second timer ends. Betting closes for 3 seconds, the wheel spins for 7, and results stay for 6.',
    'rulesZero':
        'Only the winning segment pays. Renew lets you repeat your last stakes, undo the last chip or clear while betting is open.',
    'rulesPay':
        'Multipliers are TOTAL returns, including the stake. Chances differ by weight; each segment returns 6600/8942 (73.81%) on average.',
    'rulesFair':
        'The server commits SHA-256(seed) when betting opens and reveals the seed at result. Hash seed:round with SHA-256, take the first 13 hex digits modulo 8942, then pick the weighted segment in clockwise order.',
    'seedHash': 'Round seed (hash)',
    'seed': 'Revealed seed',
    'BETTING_CLOSED': 'Bets are closed — wait for the next round.',
    'INSUFFICIENT_COINS': 'Not enough coins.',
    'BAD_TARGET': 'That is not a betting spot.',
    'BAD_AMOUNT': 'Pick a chip first.',
    'MAX_BET': 'That spot is at its maximum.',
    'BET_TOO_HIGH': 'You reached the round limit.',
    'NO_PREVIOUS': 'No previous bet to repeat.',
    'NO_BET': 'Nothing to undo.',
    'GAME_DISABLED': 'The game is paused right now.',
    'DAILY_WIN_CAP': 'You reached today\'s win cap in this game.',
    'PRIZE_POOL_LOW': 'The prize pool cannot cover this bet right now.',
    'NETWORK': 'Connection lost. Try again.',
    'FAILED': 'Something went wrong. Try again.',
    'error': 'Could not load the table. Check your connection.',
    'renew': 'Renew',
    'cancel': 'Cancel',
    'menu': 'Menu',
    'home': 'Home',
    'chance': 'Chance',
    'rank': 'Your rank',
    'win': 'WIN',
  };

  static const _arabic = {
    'mineAll': 'رهاني / الجميع',
    'title': 'عجلة السيارات',
    'ranking': 'الترتيب',
    'players': 'اللاعبون',
    'totalBet': 'إجمالي الرهان',
    'myTotalBet': 'إجمالي رهاني',
    'balance': 'الرصيد',
    'help': 'المساعدة',
    'paytable': 'جدول الدفع',
    'history': 'السجل',
    'settings': 'الإعدادات',
    'sound': 'الصوت',
    'motion': 'الحركة',
    'language': 'اللغة',
    'arabic': 'العربية',
    'english': 'English',
    'close': 'إغلاق',
    'back': 'رجوع',
    'retry': 'حاول مرة أخرى',
    'loading': 'جاري تحميل الطاولة…',
    'clear': 'مسح الرهانات',
    'undo': 'تراجع',
    'rebet': 'إعادة آخر رهان',
    'betting': 'ضع رهانك',
    'closing': 'الرهانات مغلقة — انتظر النتيجة',
    'spinning': 'جاري الدوران...',
    'result': 'النتيجة',
    'youWon': 'ربحت',
    'noWin': 'لا ربح هذه الجولة',
    'payout': 'الدفع (شامل الرهان)',
    'emptyHistory': 'لا توجد جولات بعد.',
    'emptyRanking': 'لا يوجد فائزون اليوم بعد — كن الأول!',
    'emptyPlayers': 'لا توجد رهانات على الطاولة في هذه الجولة بعد.',
    'todayNet': 'صافي ربحك اليوم',
    'bestWin': 'أكبر فوز اليوم',
    'statsNote': 'الإحصائيات السابقة لا تتنبأ بنتيجة الجولة القادمة.',
    'lastResults': 'آخر النتائج',
    'rules':
        'طاولة واحدة للجميع. اختر شريحة ثم اضغط على علامة قبل انتهاء 25 ثانية. تُغلق الرهانات 3 ثوانٍ، وتدور العجلة 7 ثوانٍ، وتظهر النتيجة 6 ثوانٍ.',
    'rulesZero':
        'يفوز القطاع المختار فقط. تجديد يتيح إعادة آخر رهان أو التراجع عن آخر شريحة أو المسح أثناء فتح الرهانات.',
    'rulesPay':
        'المضاعفات تشمل قيمة الرهان. الاحتمالات حسب الأوزان؛ العائد المتوقع لكل قطاع 6600/8942 (73.81%).',
    'rulesFair':
        'الخادم يعلن SHA-256 للبذرة عند فتح الرهانات ويكشفها مع النتيجة. احسب SHA-256 للبذرة:الجولة، ثم أول 13 رقمًا سداسيًا modulo 8942، واختر القطاع بالأوزان بترتيب الساعة.',
    'seedHash': 'بذرة الجولة (مشفّرة)',
    'seed': 'البذرة المكشوفة',
    'BETTING_CLOSED': 'الرهانات مغلقة — انتظر الجولة القادمة.',
    'INSUFFICIENT_COINS': 'رصيدك لا يكفي.',
    'BAD_TARGET': 'هذه ليست خانة رهان.',
    'BAD_AMOUNT': 'اختر شريحة أولًا.',
    'MAX_BET': 'هذه الخانة وصلت للحد الأقصى.',
    'BET_TOO_HIGH': 'وصلت للحد الأقصى للجولة.',
    'NO_PREVIOUS': 'لا يوجد رهان سابق لإعادته.',
    'NO_BET': 'لا يوجد ما تتراجع عنه.',
    'GAME_DISABLED': 'اللعبة متوقفة حاليًا.',
    'DAILY_WIN_CAP': 'وصلت للحد اليومي لمكاسبك في هذه اللعبة.',
    'PRIZE_POOL_LOW': 'صندوق الجوائز لا يغطي هذا الرهان الآن.',
    'NETWORK': 'انقطع الاتصال. حاول مرة أخرى.',
    'FAILED': 'حدث خطأ. حاول مرة أخرى.',
    'error': 'تعذر تحميل الطاولة. تحقق من الاتصال.',
    'renew': 'تجديد',
    'cancel': 'إلغاء',
    'menu': 'القائمة',
    'home': 'الرئيسية',
    'chance': 'الاحتمال',
    'rank': 'ترتيبك',
    'win': 'WIN',
  };
}
