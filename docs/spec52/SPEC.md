مواصفة تنفيذ التعديلات والإضافات الشاملة لتطبيق SAMAFOX (2026-10-20)

أولًا: قواعد عامة إلزامية قبل تنفيذ أي تعديل
1. التطبيق Flutter، لذلك يتم تنفيذ واجهة المستخدم في Flutter، لكن جميع البيانات الحساسة والصلاحيات والحسابات والجوائز والـ VIP والـ CP والوكالات يجب أن تكون Server-Side.
2. ممنوع الاعتماد على Flutter فقط في الصلاحيات؛ أي مستخدم يحاول استدعاء API مباشرة يجب أن يتم التحقق من صلاحيته من السيرفر.
3. أي تغيير في VIP أو Level أو CP أو الهدايا أو المنتجات أو الوكالات أو الجوائز يجب أن يسجل في Audit Log.
4. لا يتم حذف البيانات القديمة من قاعدة البيانات إلا إذا كان ذلك ضروريًا؛ نفضل Migration آمن حتى لا تتأثر البيانات الحالية.
5. قبل التطبيق النهائي: Backup كامل للقاعدة والكود، واختبار على Realme C3 Android 10، Realme C53 Android 14/15، Samsung A26، Wi-Fi، بيانات الهاتف، انقطاع الإنترنت، إغلاق التطبيق بالقوة، Bluetooth، سماعة سلك.
6. جميع الواجهات يجب أن تكون Responsive ولا تعتمد على مقاس شاشة ثابت.

1. مشاركة الغرفة داخل SAMAFOX
المشكلة: زر مشاركة في الإعدادات وهمي ولا ينقل المستخدم فعليًا إلى الغرفة.
أ) مشاركة مع أصدقاء SAMAFOX: عند "مشاركة الغرفة" يتم إنشاء Room Share Token يحتوي: Room ID، Inviter User ID، وقت الإنشاء، Token فريد، صلاحية، اسم الغرفة، صورة الغرفة. يتم إرسال Card داخل رسائل SAMAFOX: "فلان يدعوك للانضمام إلى غرفة: [صورة] اسم الغرفة ID الغرفة [دخول الغرفة]". عند الضغط: موجودة → فتح مباشرة؛ مغلقة → "الغرفة غير متاحة حاليًا"؛ محظور → سبب المنع؛ ممتلئة → "الغرفة ممتلئة". الاحتفاظ بـ Inviter ID.
ب) WhatsApp: رابط HTTPS حقيقي https://domain.com/room/{share_token}. مثبت → يفتح SAMAFOX ويقرأ الـ Token ويتحقق من السيرفر ويفتح الغرفة. غير مثبت → صفحة التطبيق/Google Play، وبعد التثبيت والفتح يُستكمل الـ Token (deferred). Android App Links / Deep Links. لا Firebase Dynamic Links. Domain خاص + App Links + Backend Token.
Flutter: Share UI, Share sheet, Deep Link handler, Room navigation. Backend: Create/Validate Token, Room access validation. DB: room_share_tokens.

2. تقليل الضوضاء: الخيار موجود ولا يفعل شيئًا. تفعيل Noise Suppression, Echo Cancellation, AGC, Voice Processing, High-pass filter عبر Voice SDK فعليًا على Stream الصوت، مع إعداد ON/OFF. لا يقطع صوت المتحدث.

3. السماعة والتحويل التلقائي: إلغاء زر السماعة من واجهة الغرفة. Automatic Audio Routing: سماعة سلك / Bluetooth Headset / Earbuds → تحويل الصوت والمايك تلقائيًا؛ عند الفصل → يعود للهاتف. مراقبة Route لحظيًا. Bluetooth بـ HFP → استخدم مايك السماعة؛ Output فقط → أفضل Route. تغيير السماعة لا يخرج المستخدم ولا يقطع الصوت.

4. شريط الهدية أعلى الغرف: الضغط عليه يفتح Dialog "هل تريد الانتقال إلى هذه الغرفة؟" [نعم][لا] → الانتقال إلى Room ID. Banner Event يحتوي Room ID, Gift ID, Sender ID, Receiver ID, Timestamp. غير متاحة → "الغرفة غير متاحة حاليًا."

5. Seat Lease للمايك: عند الصعود: seat_status=occupied, last_heartbeat=now, lease_expire=now+300s. Heartbeat كل 10–15 ثانية. انقطاع الإنترنت → المايك محجوز 5 دقائق، الرجوع خلالها يسترجع نفس المايك تلقائيًا، بعدها السيرفر يحرره. مغادرة الغرفة → تحرير فوري. إغلاق بالقوة → نظام الـ 5 دقائق.

6. Animated Avatar Permission من لوحة التحكم: تحديد VIP المسموح (VIP1..VIPn). التحقق Server-Side (حاليًا أي شخص يستطيع استخدامها).

7. VIP Name Colors في لوحة التحكم (VIP1 أبيض، VIP2 أخضر...)، Owner يغير اللون، HEX، ومستقبلًا Gradient. أعلى VIP يأخذ لونه؛ بدون VIP → افتراضي. السيرفر يعيد VIP + name_color.

7b. (ملاحظة) تُعرض الألوان في كل مكان يظهر فيه الاسم.

8. CP Top 30 داخل الغرفة: إزالة الصورة الحالية أعلى الغرفة التي بلا وظيفة، ومكانها CP Leaderboard صغير: Top1..Top3 (صور الثنائي + الاسم + CP Level) وزر [عرض المزيد] يفتح Top 1..30 ويطويها. الترتيب: CP Level الأعلى، ثم إجمالي Coins في أحداث CP، ثم الأسبق في الوصول للمستوى. حفظ CP Level, CP XP, CP Coins, Level Reached Timestamp.

9. كأس الغرفة وكأس البرنامج: الدعم الذاتي (sender_id == receiver_id) يُحتسب طبيعيًا في Room Cup و App Cup ويظهر في السجل. منع Double Counting: كل Transaction مرة واحدة.

10. هدايا علاقة CP: عند التفعيل يعرض فقط [صورة1] 🤝 [صورة2] و CP Level، تصميم بسيط بدون معلومات إضافية. في لوحة التحكم لكل Gift في قائمة العلاقة نوع: Activate CP / Increase CP Level Only / Both.

11. الألعاب داخل الغرفة: قائمة الألعاب 3 في الصف (صورة، اسم، حالة). اللعبة لا تتجاوز ~ثلثي الشاشة، تبدأ من أسفل، فيها X/سهم خروج يرجع للغرفة بدون الخروج منها. لا Full Screen إجباري إلا بإعداد خاص. (Olympic مختلفة، بعض الألعاب بلا زر خروج.)

12. Social System: friendships (requester_id, receiver_id, status pending/accepted/rejected/blocked, created_at, accepted_at, blocked_at)، الصديق بعد القبول فقط. follows (follower_id, following_id, created_at). يتابعني = reverse. الزوار: visitor_id, profile_owner_id, visited_at، لا زيارة للنفس، لا تكرار مبالغ (last_visit). الأرقام حقيقية من DB.

13. الاحتفاظ عند الخروج: إزالة مربع الاحتفاظ المستقل. X → "ماذا تريد أن تفعل؟" [مغادرة][احتفاظ]. زر Back → احتفاظ تلقائي.

14. Header الغرفة: مساحة أكبر، مستطيل شفاف زجاجي Premium فيه اسم الغرفة و ID: XXXXX. Responsive.

15. الضغط على صورة الغرفة → Room Info Popup: صورة، اسم، Room ID، Owner، عدد المستخدمين، عدد المايكات المستخدمة.

16. قائمة دعم جميع المايكات: تعتمد على Room Seats وليس Online Users. إظهار جميع المايكات، Owner Seat إذا كان غائبًا، أي Seat محجوز. "الجميع" يشمل جميع المايكات المستهدفة. لا إرسال لمستخدم غير موجود فعليًا إلا إذا كان النظام يسجل دعم Seat وتُسجل في الحساب الصحيح.

17. إرسال صورة كهدية: تفعيل Image Gift بصلاحية Image Gift Minimum VIP من لوحة التحكم. غير المؤهل → الأيقونة مقفولة أو مخفية حسب إعداد Owner.

18. 🔇 كتم صوت الغرفة للمستخدم فقط، لا يكتم مايكه، يستمر حتى لو تغيرت Tracks.

19. نقل أيقونة الألعاب للجانب الأيسر العلوي فوق مربعات إعدادات الغرفة، وتوسيع المساحة أسفل الغرفة.

20. Emoji متحرك: أيقونة بجانب Text Input تفتح لوحة Emoji Animations (قبلة يمين/شمال، نظارة مكبرة، تثاؤب ونوم، حزين بقلب مكسور، تصفيق، بكاء، ضحك، لافتة مرحبا، قلب، رقص، عروس وعريس، حضن، قبلة ثنائية، بصق يمين/شمال، Wow، غضب، صدمة، قلب مشتعل، ضحك قوي، نوم، احتفال، تصفيق ناري، نجوم، تاج). يظهر فوق مايك المرسل 2–4 ثوانٍ. ملفات خفيفة (Lottie/SVGA/WebP/Rive). السيرفر يرسل emoji_id, sender_id, seat_id, timestamp.

21. تشغيل الموسيقى من الجهاز: إعادة تفعيل Music Picker (MP3/M4A/WAV/AAC) مع Play/Pause/Stop/Progress/Volume، عبر Android Storage Picker بدون صلاحية ملفات كاملة، بدون كسر صوت الغرفة.

22. "خلفياتي": تظهر فقط الخلفيات المجانية + المشتراة + الممنوحة للمستخدم. الممنوحة/المشتراة لا تظهر لغيره. DB: room_backgrounds, user_background_inventory (user_id, background_id, source purchase/gift/grant, granted_by, purchased_at, expires_at, status).

23. Gift Effects / Entry Effects ON/OFF للمستخدم (Client-Side للعرض فقط)، الحدث يصل من السيرفر.

24. هدايا الفيديو: إعادة بناء Video Gift Renderer: تحميل قبل التشغيل، Cache، Preload، معالجة Codec، fallback، لا UI Thread، لا تجميد، الصوت حسب الإعداد، لا يغطي المايكات بالكامل. Fallback Format موحد للأجهزة الضعيفة (H.264 baseline).

25. Image Gift لا تصدر رنة/صوت.

26. Lucky Gift: بعد الإرسال دائرة 5 ثوانٍ بزر "إرسال مرة أخرى" مع Countdown 5..1، الخصم فقط عند نجاح Transaction، رصيد غير كافٍ → رسالة.

27. ترتيب المايكات: Tabs (الكل/الهدايا/الرسائل) كبيرة وتغطي المايكات. رفع المايكات، Tabs Compact، SafeArea + Responsive. لا شيء يغطي المايكات.

28. صاروخ الهدايا Rocket في كل غرفة فوق أيقونة الألعاب: Current/Target Coins. لوحة التحكم: Target Coins, Reward Pool, Room Cup Percentage, مدة الحدث, Products, Number of Winners, Max Reward Per User. عند الهدف: Animation وإعلان في كل الغرف، الضغط ينقل للغرفة. الجوائز من Reward Pool (Coins, Bubble, Gift, Entry Effect, Frame, Product). مرة واحدة لكل مستخدم: rocket_event_id, user_id, reward_id, claimed_at + Unique (rocket_event_id,user_id). الاحتمالات Server-Side. Audit Log لكل نتيجة.

29. PK: أيقونة فوق الصاروخ. Room PK / Global PK. صاحب الصلاحية يختار الخصم والمدة والنوع. النقاط من Coins Gifts أو Gifts محددة. لوحة التحكم: duration, gifts counted, points per coin, win condition, tie rule, rewards. أثناء PK: A VS B، Score، Progress Bar، Countdown. السيرفر يحسم ويسجل.

30. الغرف العامة: غرفتان في الصف (50%)، Card مربع. Animated Room Image بحد أدنى VIP من لوحة التحكم، تحقق Server-Side.

31. إشعار نسبة الوكيل: إزالة الشريط داخل الغرفة، Notification Icon 🔔 فوق الرسائل مع Badge، يفتح قائمة إشعارات (التاريخ، الوقت، الوكالة، النسبة، الفترة، الإنتاج، العمولة حسب الصلاحية). لا معلومات مالية لغير المخولين.

32. تسجيل الشاشة: MediaProjection، Screen Video + Mic Audio + App Audio حسب Android/SDK (Audio Mixer إن لزم). بعد Stop: MP4 في MediaStore يظهر في الاستوديو، الاسم SAMAFOX_YYYYMMDD_HHMMSS.mp4، صلاحيات حسب الإصدار.

33. الضغط على اسم المستخدم في الشات → Mini Profile: صورة، اسم، ID، VIP، Level، CP، Badge، Frame، Entry Effect. Badge لا تستبدل VIP (VIP ≠ Badge).

34. CP Gifts في لوحة التحكم: CP Activation YES/NO، CP Level Up YES/NO، CP XP Value. ليست كل هدية في قائمة CP تفعّل العلاقة.

35. وكالات المضيفين: تغيير Agency Name و Agency Image مع سجل old_name/new_name/changed_by/changed_at. Invitation State Machine: pending/accepted/rejected/expired/cancelled. rejected → دعوة جديدة ممكنة. pending → "إعادة إرسال". expired → جديدة. كل دعوة ID مستقل، لا Unique Constraint يمنع.

36. وكالات الشحن وفروعها: Branch System (Branch ID, Name, Owner, Status, Created At) يتبع Parent Agency. كل شحن يسجل Parent Agency, Branch, User, Amount, Coins, Timestamp, Transaction ID. لا وصول لبيانات Branch آخر.

37. ربط Google برقم الهاتف: Settings → Account → Link Phone Number: إدخال، OTP، تحقق، ربط بالحساب الحالي. الرقم مربوط بآخر → "هذا الرقم مرتبط بحساب آخر." Atomic. user_auth_methods (user_id, provider, provider_user_id, phone_number, verified, created_at) Unique (provider, provider_user_id) و phone_number.

38. قائمة "عام" للهدايا: كل Gift له category_id واحد؛ النقل من عام يخفيها من عام. لوحة التحكم: إدارة قوائم الهدايا (إضافة، تعديل اسم، صورة، ترتيب، حذف، نقل Gift، نقل عدة Gifts، إزالة). حذف قائمة → اختيار نقل الهدايا لعام أو فك الارتباط. لا تُحذف الهدية إلا باختيار صريح.

39. شريط مكسب الألعاب تحت/داخل Header الغرفة: "🎮 فلان لعب Olympic وكسب 20,000" من Game Transaction حقيقية. Game Win Event: user_id, room_id, game_id, game_name, win_coins, timestamp. Slide خفيف.

40. Profile Decoration Frame حول صفحة البروفايل (منطقة البروفايل)، لا يظهر كإطار غرفة ولا حول المايك. Profile Decoration Frame ≠ Avatar Frame ≠ Room Frame، كل واحد Product Type مستقل.

41. Custom Store Categories: Owner ينشئ قائمة (مثل "ID مميز") بمنتجات IDs. شراء ID: تحقق أنه غير مستخدم، Lock، خصم، Transaction، نقل ID، تغيير Display ID، تحرير القديم، سجل شراء. Create Order → Lock Item → Validation → Commit → Assign ID؛ فشل → Rollback. لوحة التحكم: قائمة (اسم، صورة، ترتيب)، منتج (اسم، صورة، سعر، عملة، مدة، مخزون، Available/Unavailable، حذف، تعديل سعر). منفصل عن صلاحيات Manager/Super Admin/Admin.

42. صلاحيات لوحة التحكم: فصل Role عن Permission، Owner تحكم كامل. Manager/Super Admin/Admin لا يعدلون الأسعار/العملات/Coins/Recharge/إعدادات وكالات الشحن المالية/Store Products إلا بصلاحية صريحة من Owner.

43. Audit Log: admin_id, action, target_type, target_id, old_value, new_value, ip, device, created_at لكل عملية مهمة (VIP، لون اسم، منح Frame/Gift، Agency Name، Gift Category، Store Product، Product Price، CP Gift، VIP requirement).

44. الأداء: لا Animation يسبب Lag على UI Thread (Video Gifts, Frames, Emoji, Entry/Gift Effects, Background, Rocket, PK). Cache/Preload. الهدية لا تُخرج المستخدم ولا تقطع الصوت ولا تجمد المايكات ولا الشات.

45. Gift Event موحد: gift_id, gift_type, sender_id, receiver_id, room_id, seat_id, animation_url, sound_url, duration, effect_type, cp_activate, cp_xp, target_type, created_at, transaction_id. Flutter يعرض حسب النوع.

46. منع تكرار معاملات الهدايا: transaction_id Unique، Retry لا يخصم مرتين، السيرفر يعيد نفس النتيجة.

47. Reconnect للغرفة: عند انقطاع WebSocket 5 محاولات مع Backoff، استرجاع Room Session + Seat + Audio Session. بعد 5 دقائق تحرير المايك. تسجيل سبب الخروج.

48. Room Session Monitoring: User ID, Room ID, Join Time, Last Heartbeat, WebSocket State, Voice State, Seat ID, Last API, Disconnect Reason, Reconnect Count.

49. اختبار القبول النهائي (الغرفة، الصوت، الهدايا، VIP، CP، الألعاب، Social، الوكالات، المتجر).

50. التسليم: APK، قائمة APIs المعدلة، Migration، الجداول/الحقول الجديدة، الصلاحيات الجديدة، Screenshots، فيديو، اختبار الأجهزة، عدم حذف بيانات.

51. الأنظمة مترابطة: Room↔User↔Seat↔Voice Session↔Gift↔CP↔VIP↔Agency↔Store↔Notification↔Audit Log. كل عملية مالية/مكافأة/هدية/CP/ID/منتج Server-Side و Atomic و Idempotent.

52. بند ناقص ("ودعوة ال...") — لم يصل كاملًا، لا يُنفذ.
