class FruitWheelStrings {
  final bool ar;
  const FruitWheelStrings(this.ar);
  String text(String key) => (ar ? _arabic : _english)[key] ?? key;
  String get footer => ar
      ? 'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب، ولا توجد جوائز مالية حقيقية.'
      : 'Runs on SamaFox coins — they do not convert to money or withdraw; no real-money prizes.';
  String round(int n) => ar ? 'الجولة: $n' : 'Round: $n';
  String rank(int? n) {
    if (n == null) return '—';
    if (ar) return '$n';
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix = teen
        ? 'th'
        : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suffix';
  }

  String orbValue(int multiplier) => '×$multiplier';

  static const _english = {
    'title': 'FRUIT WHEEL',
    'spin': 'SPIN',
    'repeat': 'REPEAT',
    'spinning': 'Spinning…',
    'balance': 'Balance',
    'coins': 'coins',
    'recharge': 'Recharge',
    'new': 'NEW',
    'help': 'Help',
    'history': 'History',
    'settings': 'Settings',
    'leaders': 'Top players',
    'sound': 'Sound',
    'soundOn': 'Sound on',
    'soundOff': 'Sound off',
    'motion': 'Motion',
    'language': 'Language',
    'arabic': 'العربية',
    'english': 'English',
    'clearHistory': 'Clear history',
    'close': 'Close',
    'back': 'Back',
    'continue': 'Continue',
    'clear': 'Clear',
    'retry': 'Try again',
    'loading': 'Loading game…',
    'placeBets': 'Pick a chip, then tap a card to bet.',
    'tapRepeat': 'Tap REPEAT to play your last bets again.',
    'yourBet': 'Your bet',
    'today': "Today's bets",
    'won': 'You won',
    'lost': 'No win this round',
    'bonus': 'BONUS',
    'bonusTitle': 'Bonus round',
    'bonusPick': 'Pick an orb',
    'bonusPrize': 'Bonus prize',
    'weekRank': 'Weekly rank',
    'resetsIn': 'Resets in',
    'emptyBoard': 'No winners yet this week — be the first!',
    'emptyHistory': 'No rounds yet.',
    'maxBet': 'Maximum bet reached',
    'watermelon': 'Watermelon',
    'plum': 'Plum',
    'sevens': '777',
    'outcome': 'Result',
    'bet': 'Bet',
    'prize': 'Prize',
    'fairness': 'Fairness',
    'seedHash': 'Server seed (hash)',
    'clientSeed': 'Your seed',
    'nonce': 'Rounds on this seed',
    'rotate': 'Reveal & new seed',
    'revealed': 'Revealed server seed',
    'rules':
        'Pick a chip and tap Watermelon, 777 or Plum — you can bet on more than one card. Press SPIN. The wheel stops on one outcome: the matching card pays its bet × its multiplier (bet included); the other cards lose.',
    'odds':
        'Watermelon and Plum pay ×2, 777 pays ×3. Every card returns the same average share of what is bet on it; no card is a better bet.',
    'bonusHelp':
        'BONUS: card bets do not win, and you open one of three orbs worth ×2, ×3 or ×5 of a tenth of your total bet. The orb value is decided when the wheel stops; the one you tap reveals it.',
    'repeatHelp':
        'After a round the table clears. REPEAT places the same chips again and spins.',
    'stopHelp':
        'Tap the wheel while it spins to skip the animation. The result was already decided by the server and never changes.',
    'fairHelp':
        'Every round is drawn from your server seed (shown as a hash before you play), your seed and a counter. Reveal the seed at any time to check past rounds.',
    'rtp': 'Average return',
    'limits': 'Bet per round',
    'dailyCap': 'Daily win cap',
    'unlimited': 'Unlimited',
    'error': 'Could not load the game. Check your connection.',
    'INSUFFICIENT': 'Not enough coins for this bet.',
    'BAD_BET': 'This bet is not allowed.',
    'GAME_DISABLED': 'The game is paused right now.',
    'DAILY_WIN_CAP': 'You reached today\'s win cap in this game.',
    'PRIZE_POOL_LOW': 'The prize pool cannot cover this bet right now. Try a smaller bet.',
    'NETWORK': 'Connection lost. Your round will settle when you are back.',
    'FAILED': 'Something went wrong. Try again.',
  };

  static const _arabic = {
    'title': 'عجلة الفواكه',
    'spin': 'دوّر',
    'repeat': 'كرر',
    'spinning': 'جاري الدوران...',
    'balance': 'الرصيد',
    'coins': 'عملة',
    'recharge': 'إعادة الشحن',
    'new': 'جديد',
    'help': 'المساعدة',
    'history': 'السجل',
    'settings': 'الإعدادات',
    'leaders': 'أفضل اللاعبين',
    'sound': 'الصوت',
    'soundOn': 'تشغيل الصوت',
    'soundOff': 'كتم الصوت',
    'motion': 'الحركة',
    'language': 'اللغة',
    'arabic': 'العربية',
    'english': 'English',
    'clearHistory': 'مسح السجل',
    'close': 'إغلاق',
    'back': 'رجوع',
    'continue': 'متابعة',
    'clear': 'مسح',
    'retry': 'حاول مرة أخرى',
    'loading': 'جاري تحميل اللعبة…',
    'placeBets': 'اختر شريحة ثم اضغط على بطاقة للرهان.',
    'tapRepeat': 'اضغط «كرر» لتلعب رهانك السابق مرة أخرى.',
    'yourBet': 'رهانك',
    'today': 'رهانات اليوم',
    'won': 'ربحت',
    'lost': 'لا فوز هذه الجولة',
    'bonus': 'مكافأة',
    'bonusTitle': 'جولة المكافأة',
    'bonusPick': 'اختر كرة',
    'bonusPrize': 'جائزة المكافأة',
    'weekRank': 'ترتيبك الأسبوعي',
    'resetsIn': 'يتجدد بعد',
    'emptyBoard': 'لا يوجد فائزون هذا الأسبوع بعد — كن الأول!',
    'emptyHistory': 'لا توجد جولات بعد.',
    'maxBet': 'وصلت للحد الأقصى للرهان',
    'watermelon': 'بطيخ',
    'plum': 'برقوق',
    'sevens': '777',
    'outcome': 'النتيجة',
    'bet': 'الرهان',
    'prize': 'الجائزة',
    'fairness': 'العدالة',
    'seedHash': 'بذرة الخادم (مشفّرة)',
    'clientSeed': 'بذرتك',
    'nonce': 'الجولات على هذه البذرة',
    'rotate': 'اكشف البذرة وابدأ بذرة جديدة',
    'revealed': 'بذرة الخادم المكشوفة',
    'rules':
        'اختر شريحة واضغط على البطيخ أو 777 أو البرقوق — يمكنك الرهان على أكثر من بطاقة. اضغط «دوّر». تتوقف العجلة على نتيجة واحدة: البطاقة المطابقة تدفع رهانها × مضاعفها (شاملًا الرهان)، وباقي البطاقات تخسر.',
    'odds':
        'البطيخ والبرقوق ×2، و777 ×3. كل بطاقة تُرجع نفس متوسط النسبة مما يُراهن عليها؛ لا توجد بطاقة أفضل من غيرها.',
    'bonusHelp':
        'المكافأة: لا تربح رهانات البطاقات، وتفتح كرة من ثلاث قيمتها ×2 أو ×3 أو ×5 من عُشر رهانك الكلي. تُحدَّد القيمة عند توقف العجلة، والكرة التي تختارها تكشفها.',
    'repeatHelp': 'بعد كل جولة تُمسح الطاولة. زر «كرر» يضع نفس الشرائح ويدوّر.',
    'stopHelp':
        'اضغط على العجلة أثناء الدوران لتخطي الحركة. النتيجة حددها الخادم مسبقًا ولا تتغير.',
    'fairHelp':
        'كل جولة تُسحب من بذرة الخادم (تظهر مشفّرة قبل اللعب) وبذرتك وعدّاد. اكشف البذرة متى شئت لتتحقق من جولاتك السابقة.',
    'rtp': 'متوسط العائد',
    'limits': 'الرهان في الجولة',
    'dailyCap': 'الحد اليومي للمكاسب',
    'unlimited': 'غير محدود',
    'error': 'تعذر تحميل اللعبة. تحقق من الاتصال.',
    'INSUFFICIENT': 'رصيدك لا يكفي لهذا الرهان.',
    'BAD_BET': 'هذا الرهان غير مسموح.',
    'GAME_DISABLED': 'اللعبة متوقفة حاليًا.',
    'DAILY_WIN_CAP': 'وصلت للحد اليومي لمكاسبك في هذه اللعبة.',
    'PRIZE_POOL_LOW': 'صندوق الجوائز لا يغطي هذا الرهان الآن. جرّب رهانًا أصغر.',
    'NETWORK': 'انقطع الاتصال. ستُسوّى جولتك عند عودتك.',
    'FAILED': 'حدث خطأ. حاول مرة أخرى.',
  };
}
