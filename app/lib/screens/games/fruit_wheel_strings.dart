class FruitWheelStrings {
  final bool ar;
  const FruitWheelStrings(this.ar);
  String text(String key) => (ar ? _arabic : _english)[key] ?? key;
  String get footer => ar
      ? 'يعمل بعملات سمافوكس — لا تُحوَّل إلى نقود ولا تُسحب، ولا توجد جوائز مالية حقيقية.'
      : 'Runs on SamaFox coins — they do not convert to money or withdraw; no real-money prizes.';
  String round(int n) => ar ? 'الجولة: $n' : 'Round: $n';
  String bonusCountdown(int n) => ar
      ? (n == 0 ? 'لفة المكسب المزدوج!' : 'المكسب المزدوج بعد $n لفة')
      : (n == 0 ? 'Bonus round!' : 'Double win in $n rounds');
  String bonusBanner(String kind) => kind == 'triple'
      ? (ar ? '🔥 مكسب ثلاثي!' : '🔥 Triple win!')
      : (ar ? '🎉 مكسب مزدوج!' : '🎉 Double win!');
  String rank(int? n) {
    if (n == null) return '—';
    if (ar) return '$n';
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix = teen
        ? 'th'
        : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suffix';
  }

  static const _english = {
    'win': 'Win',
    'goodLuck': 'Good luck',
    'totalBet': 'Table bets',
    'repeatBets': 'Repeat bets',
    'undo': 'Undo',
    'result': 'Results',
    'closing': 'Betting closed',
    'betting': 'Place your bets',
    'urgent': 'Time is almost up',
    'BAD_AMOUNT': 'Invalid chip.',
    'BAD_TARGET': 'Invalid card.',
    'NO_BET': 'No chip to undo.',
    'NO_PREVIOUS': 'No previous bets.',
    'BETTING_CLOSED': 'Betting closed. Wait for the next round.',
    'INSUFFICIENT_COINS': 'Not enough coins.',
    'MAX_BET': 'Maximum bet on this card reached.',
    'MAX_CARDS': 'You can bet on only two cards per round.',
    'poolHelp':
        'The program takes 30% of stakes; 70% goes to this game’s prize pool. All prizes are paid only from that pool.',
    'NETWORK':
        'Connection lost. Your balance and stakes will refresh from the server.',
    'limits': 'Bet per card',
    'emptyBoard': 'No winners today yet.',
    'weekRank': 'Daily rank',
    'fairHelp':
        'The server commits the seed hash before betting. The result comes from SHA-256(seed:round number), using the published weights. The seed is revealed at result.',
    'repeatHelp':
        'Undo and clear refund chips during betting. Repeat bets adds your previous stakes to this round; it never starts a spin.',
    'odds':
        'Watermelon: 43.75% ×1.6. Plum: 43.75% ×1.6. 77: 12.5% ×5.6. Each card has an average return of 70% before bonus rounds; the equal wheel wedges are presentation only.',
    'rules':
        'One shared table: 15 seconds to bet, 1 second closing, 6 seconds spinning, then 5 seconds of results. Choose a chip and tap at most two cards. The wheel spins automatically and every spin lands on a fruit card. Returns include the winning stake. Bonus rounds can award two or three winning cards, depending on available prize funds. Empty rounds do not advance the bonus countdown. Wins on your winning cards are added together, subject to the game limits.',
    'title': 'FRUIT WHEEL',
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
    'close': 'Close',
    'back': 'Back',
    'continue': 'Continue',
    'clear': 'Clear',
    'retry': 'Try again',
    'loading': 'Loading game…',
    'placeBets': 'Pick a chip, then tap a card to bet.',
    'yourBet': 'Your bet',
    'today': "Today's bets",
    'won': 'You won',
    'lost': 'No win this round',
    'resetsIn': 'Resets in',
    'emptyHistory': 'No rounds yet.',
    'maxBet': 'Maximum bet reached',
    'watermelon': 'Watermelon',
    'plum': 'Plum',
    'sevens': '77',
    'outcome': 'Result',
    'bet': 'Bet',
    'prize': 'Prize',
    'fairness': 'Fairness',
    'seedHash': 'Server seed (hash)',
    'revealed': 'Revealed server seed',
    'rtp': 'Average return',
    'dailyCap': 'Daily win cap',
    'unlimited': 'Unlimited',
    'error': 'Could not load the game. Check your connection.',
    'INSUFFICIENT': 'Not enough coins for this bet.',
    'BAD_BET': 'This bet is not allowed.',
    'GAME_DISABLED': 'The game is paused right now.',
    'DAILY_WIN_CAP': 'You reached today\'s win cap in this game.',
    'PRIZE_POOL_LOW':
        'The prize pool cannot cover this bet right now. Try a smaller bet.',
    'FAILED': 'Something went wrong. Try again.',
  };

  static const _arabic = {
    'win': 'فوز',
    'goodLuck': 'حظاً سعيداً',
    'totalBet': 'رهانات الطاولة',
    'repeatBets': 'إعادة الرهان',
    'undo': 'تراجع',
    'result': 'النتائج',
    'closing': 'أُغلقت الرهانات',
    'betting': 'ضع رهانك',
    'urgent': 'الوقت قرب يخلص',
    'BAD_AMOUNT': 'شريحة غير صحيحة',
    'BAD_TARGET': 'بطاقة غير صحيحة',
    'NO_BET': 'لا يوجد رهان للتراجع عنه',
    'NO_PREVIOUS': 'لا يوجد رهان سابق',
    'BETTING_CLOSED': 'أُغلقت الرهانات، انتظر الجولة التالية',
    'INSUFFICIENT_COINS': 'رصيدك لا يكفي',
    'MAX_BET': 'وصلت للحد الأقصى لهذه البطاقة',
    'MAX_CARDS': 'تقدر تراهن على خيارين بس في الجولة',
    'poolHelp':
        'يحصل البرنامج على 30% من الرهانات ويذهب 70% لصندوق جوائز اللعبة. تُدفع كل الجوائز من هذا الصندوق فقط.',
    'NETWORK': 'انقطع الاتصال. سيُحدَّث رصيدك ورهاناتك من الخادم.',
    'limits': 'الرهان لكل بطاقة',
    'emptyBoard': 'لا يوجد فائزون اليوم بعد.',
    'weekRank': 'ترتيبك اليومي',
    'fairHelp':
        'يلتزم الخادم ببصمة البذرة قبل الرهان. تُسحب النتيجة من SHA-256(seed:round number) وفق الأوزان المنشورة وتُكشف البذرة عند النتيجة.',
    'repeatHelp':
        'التراجع والمسح يعيدان الشرائح أثناء الرهان. إعادة الرهان تضيف رهانات الجولة السابقة لهذه الجولة ولا تبدأ الدوران.',
    'odds':
        'البطيخ: 43.75% ×1.6. البرقوق: 43.75% ×1.6. 77: ‏12.5% ×5.6. متوسط عائد كل بطاقة 70% قبل لفات المكسب الإضافي؛ القطاعات المتساوية للعرض فقط.',
    'rules':
        'طاولة واحدة للجميع: 15 ثانية للرهان، ثانية للإغلاق، 6 ثوانٍ للدوران، ثم 5 ثوانٍ للنتائج. اختر شريحة واضغط على خيارين كحد أقصى. العجلة تدور تلقائيًا وكل لفة تقف على بطاقة فواكه. العائد يشمل الرهان الفائز. لفات المكسب الإضافي قد تفوز فيها بطاقتان أو ثلاث حسب الرصيد المتاح للجوائز. اللفات الفارغة لا تقدّم عداد المكسب الإضافي. تُجمع مكاسب بطاقاتك الفائزة مع تطبيق حدود اللعبة.',
    'title': 'عجلة الفواكه',
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
    'close': 'إغلاق',
    'back': 'رجوع',
    'continue': 'متابعة',
    'clear': 'مسح',
    'retry': 'حاول مرة أخرى',
    'loading': 'جاري تحميل اللعبة…',
    'placeBets': 'اختر شريحة ثم اضغط على بطاقة للرهان.',
    'yourBet': 'رهانك',
    'today': 'رهانات اليوم',
    'won': 'ربحت',
    'lost': 'لا فوز هذه الجولة',
    'resetsIn': 'يتجدد بعد',
    'emptyHistory': 'لا توجد جولات بعد.',
    'maxBet': 'وصلت للحد الأقصى للرهان',
    'watermelon': 'بطيخ',
    'plum': 'برقوق',
    'sevens': '77',
    'outcome': 'النتيجة',
    'bet': 'الرهان',
    'prize': 'الجائزة',
    'fairness': 'العدالة',
    'seedHash': 'بذرة الخادم (مشفّرة)',
    'revealed': 'بذرة الخادم المكشوفة',
    'rtp': 'متوسط العائد',
    'dailyCap': 'الحد اليومي للمكاسب',
    'unlimited': 'غير محدود',
    'error': 'تعذر تحميل اللعبة. تحقق من الاتصال.',
    'INSUFFICIENT': 'رصيدك لا يكفي لهذا الرهان.',
    'BAD_BET': 'هذا الرهان غير مسموح.',
    'GAME_DISABLED': 'اللعبة متوقفة حاليًا.',
    'DAILY_WIN_CAP': 'وصلت للحد اليومي لمكاسبك في هذه اللعبة.',
    'PRIZE_POOL_LOW':
        'صندوق الجوائز لا يغطي هذا الرهان الآن. جرّب رهانًا أصغر.',
    'FAILED': 'حدث خطأ. حاول مرة أخرى.',
  };
}
