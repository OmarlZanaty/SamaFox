import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../repositories/cp_repository.dart';
import '../../screens/store_screen.dart';
import '../models/gift.dart';
import '../services/gift_repository.dart';

/// A recipient candidate for the gift picker.
class GiftRecipient {
  final int id;
  final String name;
  final String? avatarUrl;
  final int? seatNumber;
  const GiftRecipient({required this.id, required this.name, this.avatarUrl, this.seatNumber});
}

const _kGoldColor = Color(0xFFF5C242);
const _kBgColor = Color(0xFF0B0B10);
const _kCardColor = Color(0xFF17171F);
const _kBorderColor = Color(0xFF2A2A35);

// Recipient scope: which pool of room users the avatar row/target draws from.
enum _RecipientScope { allRoom, micOnly }

/// أسماء قوائم الهدايا الاحتياطية.
///
/// B4 — the tabs now come from لوحة التحكم with the gift catalog, so a list the
/// owner creates appears without an app release. This map is only the fallback
/// for a server that predates gift lists, and for a gift whose category was
/// deleted; without it such a gift would sit under a tab labelled with its raw
/// key.
const Map<String, String> _kCategoryLabels = {
  'all': 'عادي',
  'love': 'العلاقة',
  'luxury': 'خاص',
  'lucky': 'محظوظ',
  'magic': 'ماجيك',
  'flag': 'علم',
  'bag': 'كيس',
  'fun': 'مرح',
  'festive': 'مناسبات',
  'cp': 'CP',
  'vip': 'VIP',
  'RELATION_RING': 'خاتم العلاقة',
};

/// The gift list that carries CP gifts. Matches the `cp` key seeded into
/// gift_categories, which is also what the dashboard's CP list uses.
const String _kCpCategoryKey = 'cp';

/// ترتيب التبويبات الثابت.
const List<String> _kKnownCategories = [
  'love', 'luxury', 'lucky', 'magic', 'flag', 'bag', 'fun', 'festive',
  'cp', 'vip', 'RELATION_RING',
];

/// قوائم تظهر دائماً حتى لو لم تُضف لها هدايا بعد.
const Set<String> _kAlwaysShownCategories = {'cp', 'vip'};

String _categoryLabel(String key) => _kCategoryLabels[key] ?? key;

/// Bottom-sheet gift picker: recipient-scope selector, category tabs, gift
/// grid, quantity dropdown and coin balance/recharge footer.
class GiftPickerSheet extends StatefulWidget {
  const GiftPickerSheet({
    super.key,
    required this.repository,
    required this.recipients,
    this.roomId,
    required this.balance,
    required this.onBalanceChanged,
    this.initialRecipientIds = const [],
  });

  final GiftRepository repository;
  final List<GiftRecipient> recipients;
  final int? roomId;
  final int balance;
  final void Function(int newBalance) onBalanceChanged;
  final List<int> initialRecipientIds;

  static Future<void> show(
    BuildContext context, {
    required GiftRepository repository,
    required List<GiftRecipient> recipients,
    int? roomId,
    required int balance,
    required void Function(int) onBalanceChanged,
    List<int> initialRecipientIds = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: _kBgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          // Dialog is only half the screen.
          height: MediaQuery.of(context).size.height * 0.5,
          child: GiftPickerSheet(
            repository: repository,
            recipients: recipients,
            roomId: roomId,
            balance: balance,
            onBalanceChanged: onBalanceChanged,
            initialRecipientIds: initialRecipientIds,
          ),
        ),
      ),
    );
  }

  @override
  State<GiftPickerSheet> createState() => _GiftPickerSheetState();
}

class _GiftPickerSheetState extends State<GiftPickerSheet> with SingleTickerProviderStateMixin {
  TabController? _tab;
  List<String> _tabKeys = const [];
  Future<GiftCatalog>? _catalog;
  int _balance = 0;
  String? _selectedGiftId;

  /// A15 — true when the picked gift belongs to the CP list. A CP gift does not
  /// go through the normal send path at all: it raises an invitation the
  /// recipient must answer, and only then is anyone charged.
  bool _selectedGiftIsCp = false;
  static const List<int> _kQuantities = [1, 7, 10, 20, 50];
  int _quantity = _kQuantities.first;
  int _selectedGiftCost = 0; // coin cost of the currently selected gift (for optimistic deduction)
  bool _sending = false;
  late Set<int> _selectedRecipientIds;
  _RecipientScope _scope = _RecipientScope.allRoom;

  /// Tab labels straight from لوحة التحكم, keyed by category key. Empty when
  /// the server has no gift lists, in which case [_kCategoryLabels] is used.
  Map<String, String> _serverLabels = const {};

  String _tabLabel(String key) =>
      key == 'all' ? 'عادي' : (_serverLabels[key] ?? _categoryLabel(key));

  // Anchors so the popups open next to their button, not at a fixed screen spot.
  final CpRepository _cpRepository = CpRepository();

  final GlobalKey _scopeKey = GlobalKey();
  final GlobalKey _quantityKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _catalog = widget.repository.fetchCatalog();
    _selectedRecipientIds = {
      ...widget.initialRecipientIds.where(
        (id) => widget.recipients.any((r) => r.id == id),
      ),
    };
    if (_selectedRecipientIds.isEmpty && widget.recipients.isNotEmpty) {
      _selectedRecipientIds.add(widget.recipients.first.id);
    }
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  List<GiftRecipient> get _scopedRecipients => _scope == _RecipientScope.micOnly
      ? widget.recipients.where((r) => r.seatNumber != null).toList()
      : widget.recipients;

  String _resolveIconUrl(String iconUrl) {
    if (iconUrl.isEmpty) return iconUrl;
    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) return iconUrl;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return iconUrl.startsWith('/') ? '$base$iconUrl' : '$base/$iconUrl';
  }

  String? _resolveAvatarUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  List<Gift> _giftsForTab(GiftCatalog catalog, String key) {
    final all = catalog.all;
    if (key == 'all') return all;
    return all.where((g) => (g.category ?? '') == key).toList();
  }

  void _ensureTabController(GiftCatalog catalog) {
    final fromData =
        catalog.all.map((g) => g.category ?? '').where((c) => c.isNotEmpty).toSet();

    late final List<String> ordered;
    if (catalog.categories.isNotEmpty) {
      // B4 — the dashboard owns the tabs and their order. Every configured list
      // is shown even while empty: a list is created BEFORE its gifts are moved
      // into it, and a tab that vanishes until someone fills it looks broken.
      // A category still stuck on a gift but no longer configured is appended,
      // so deleting a list can never hide the gifts that were in it.
      final configured = catalog.categories.map((c) => c.key).toList();
      _serverLabels = {for (final c in catalog.categories) c.key: c.nameAr};
      ordered = <String>[
        ...configured,
        ...fromData.where((c) => !configured.contains(c)),
      ];
    } else {
      // Fallback for a server without gift lists — the previous behaviour,
      // unchanged.
      _serverLabels = const {};
      ordered = <String>[
        for (final k in _kKnownCategories)
          if (_kAlwaysShownCategories.contains(k) || fromData.contains(k)) k,
        ...fromData.where((c) => !_kKnownCategories.contains(c)),
      ];
    }

    final keys = ['all', ...ordered];
    if (_tab != null && _tabKeys.length == keys.length && _tabKeys.every(keys.contains)) return;
    _tabKeys = keys;
    _tab?.dispose();
    _tab = TabController(length: keys.length, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBgColor,
      child: Column(
        children: [
          _recipientsHeader(),
          FutureBuilder<GiftCatalog>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
                return const SizedBox.shrink();
              }
              _ensureTabController(snapshot.data!);
              return TabBar(
                controller: _tab,
                isScrollable: true,
                indicatorColor: _kGoldColor,
                indicatorWeight: 2.5,
                labelColor: _kGoldColor,
                unselectedLabelColor: Colors.white60,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: _tabKeys.map((k) => Tab(text: _tabLabel(k))).toList(),
              );
            },
          ),
          Expanded(
            child: FutureBuilder<GiftCatalog>(
              future: _catalog,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: _kGoldColor));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('فشل تحميل الهدايا: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70)),
                  );
                }
                final catalog = snapshot.data!;
                if (_tab == null) return const SizedBox.shrink();
                return TabBarView(
                  controller: _tab,
                  children: _tabKeys.map((key) {
                    final gifts = _giftsForTab(catalog, key);
                    if (gifts.isEmpty) {
                      return const Center(
                          child: Text('لا توجد هدايا بعد', style: TextStyle(color: Colors.white60)));
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: gifts.length,
                      itemBuilder: (_, i) => _giftCell(gifts[i]),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  /// Builds the anchor rect for a popup so it opens ATTACHED to [key]'s widget
  /// instead of at a hardcoded screen coordinate (which floated the menu up to
  /// the top of the screen, far away from the button that opened it).
  RelativeRect _menuPositionFor(GlobalKey key, {bool above = false}) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = key.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || button == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final overlaySize = overlay.size;
    return above
        // Open upwards from the button's top edge (for the bottom bar).
        ? RelativeRect.fromLTRB(
            topLeft.dx,
            overlaySize.height - topLeft.dy,
            overlaySize.width - bottomRight.dx,
            0,
          )
        // Open downwards from the button's bottom edge.
        : RelativeRect.fromLTRB(
            topLeft.dx,
            bottomRight.dy,
            overlaySize.width - bottomRight.dx,
            0,
          );
  }

  void _showScopeMenu() async {
    final selected = await showMenu<_RecipientScope>(
      context: context,
      position: _menuPositionFor(_scopeKey),
      color: _kCardColor,
      items: const [
        PopupMenuItem(value: _RecipientScope.allRoom, child: Text('جميع الغرفة', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: _RecipientScope.micOnly, child: Text('الميك الكامل', style: TextStyle(color: Colors.white))),
      ],
    );
    if (selected != null) {
      setState(() {
        _scope = selected;
        // A27 — BOTH options are bulk selections, not filters. The client's
        // rule: "الميك الكامل" picks everyone on a mic and "جميع الغرفة" picks
        // everyone in the room, "سواء على المايك أو تحت في الشات". Previously
        // only the mic option selected anyone, which is why "جميع الغرفة"
        // looked non-functional: it narrowed the avatar row and left the single
        // previously-selected person as the only recipient.
        //
        // Re-picking the same option is allowed (no `selected != _scope` guard)
        // so tapping it again re-selects anyone who joined since.
        _selectedRecipientIds = _scopedRecipients.map((r) => r.id).toSet();
      });
    }
  }

  Widget _recipientsHeader() {
    final recipients = _scopedRecipients;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderColor)),
      ),
      // Single row: scope dropdown (right in RTL) → recipient avatars → close.
      child: SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              key: _scopeKey,
              onTap: _showScopeMenu,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _scope == _RecipientScope.allRoom ? 'جميع الغرفة' : 'الميك الكامل',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: recipients.isEmpty
                  ? const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text('لا يوجد مستلمون',
                          style: TextStyle(color: Colors.white60, fontSize: 12)),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recipients.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _recipientChip(recipients[i]),
                    ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.close, color: Colors.white54, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientChip(GiftRecipient r) {
    final selected = _selectedRecipientIds.contains(r.id);
    final avatarUrl = _resolveAvatarUrl(r.avatarUrl);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedRecipientIds.remove(r.id);
          } else {
            _selectedRecipientIds.add(r.id);
          }
        });
      },
      child: SizedBox(
        width: 46,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _kGoldColor : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [const BoxShadow(color: _kGoldColor, blurRadius: 6, spreadRadius: 1)]
                    : null,
              ),
              padding: const EdgeInsets.all(1.5),
              child: ClipOval(
                child: avatarUrl != null
                    ? Image.network(avatarUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(r.name))
                    : _avatarFallback(r.name),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              r.seatNumber != null ? '${r.seatNumber}' : r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _kGoldColor : Colors.white70,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final initial = name.trim().isNotEmpty ? name.trim().characters.first.toUpperCase() : '?';
    return Container(
      color: const Color(0xFF2A2A35),
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
    );
  }

  bool _isNew(Gift gift) {
    final created = gift.createdAt;
    if (created == null) return false;
    return DateTime.now().difference(created) <= const Duration(days: 7);
  }

  Widget _giftCell(Gift gift) {
    final selected = _selectedGiftId == gift.id;
    final resolvedUrl = _resolveIconUrl(gift.iconUrl);
    return GestureDetector(
      onTap: () => setState(() {
        _selectedGiftId = gift.id;
        _selectedGiftCost = gift.coinCost;
        _selectedGiftIsCp = (gift.category ?? '').toLowerCase() == _kCpCategoryKey;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _kCardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kGoldColor : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: resolvedUrl.isNotEmpty
                        ? Image.network(resolvedUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _giftFallback(gift))
                        : _giftFallback(gift),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    children: [
                      Text(
                        gift.nameAr ?? gift.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🪙', style: TextStyle(fontSize: 9)),
                          const SizedBox(width: 3),
                          Text('${gift.coinCost}',
                              style: const TextStyle(color: _kGoldColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isNew(gift))
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _giftFallback(Gift gift) {
    String emoji;
    switch (gift.category) {
      case 'love': emoji = '💖'; break;
      case 'luxury': emoji = '💎'; break;
      case 'fun': emoji = '🎉'; break;
      case 'festive': emoji = '🎆'; break;
      default: emoji = '🎁';
    }
    return Container(
      color: const Color(0xFF20202B),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 28)),
    );
  }

  void _showQuantityMenu() async {
    final selected = await showMenu<int>(
      context: context,
      // Opens upwards — the button lives in the sheet's bottom bar.
      position: _menuPositionFor(_quantityKey, above: true),
      color: _kCardColor,
      items: _kQuantities
          .map((q) => PopupMenuItem(value: q, child: Text('x$q', style: const TextStyle(color: Colors.white))))
          .toList(),
    );
    if (selected != null) setState(() => _quantity = selected);
  }

  Widget _footer() {
    final disabled = _selectedGiftId == null || _selectedRecipientIds.isEmpty || _sending;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _kBorderColor)),
        ),
        child: Row(
          children: [
            // Balance + recharge — first child renders on the RIGHT in RTL.
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StoreScreen()),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_left, color: Colors.white54, size: 16),
                  const SizedBox(width: 2),
                  const Text('🪙', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(_balance.toString(),
                      style: const TextStyle(color: _kGoldColor, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Send button with attached quantity dropdown — last, renders on the LEFT in RTL.
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          onTap: disabled ? null : _send,
                          child: Center(
                            child: _sending
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(
                                    _selectedRecipientIds.length > 1
                                        ? 'إرسال (${_selectedRecipientIds.length})'
                                        : 'إرسال',
                                    style: const TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 24, color: Colors.white24),
                    Material(
                      key: _quantityKey,
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        onTap: _showQuantityMenu,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                              const SizedBox(width: 2),
                              Text('$_quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final giftId = _selectedGiftId;
    final recipients = _selectedRecipientIds.toList();
    if (giftId == null || recipients.isEmpty) return;

    // Optimistic deduction: reflect the spend instantly so the balance doesn't
    // lag behind the tap (pro-app pattern). The server's authoritative balance
    // reconciles it below; on total failure we restore the pre-send value.
    //
    // A27 — the cost of a fan-out is price × quantity × RECIPIENTS: every
    // person on the list receives the whole gift, they do not share one.
    final int prevBalance = _balance;
    final int optimisticCost = _selectedGiftCost * _quantity * recipients.length;
    setState(() {
      _sending = true;
      _balance = (_balance - optimisticCost).clamp(0, 1 << 62);
    });
    widget.onBalanceChanged(_balance);

    try {
      if (_selectedGiftIsCp) {
        await _sendCp(giftId, recipients, prevBalance);
      } else if (recipients.length == 1) {
        await _sendSingle(giftId, recipients.first, prevBalance);
      } else {
        await _sendMany(giftId, recipients, prevBalance);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A15 — a CP gift is an invitation, not a transfer.
  ///
  /// Nothing is charged here: the recipient decides, and the server takes the
  /// full price on accept or 30% of it on reject. So the optimistic deduction
  /// applied in [_send] is undone immediately — showing the coins gone while
  /// the other person has not answered would be wrong twice over (they may
  /// reject, in which case only 30% goes).
  ///
  /// A CP pairing is between two people, so this deliberately does not fan out:
  /// if a bulk scope was selected, only the first recipient is invited.
  Future<void> _sendCp(String giftId, List<int> recipients, int prevBalance) async {
    setState(() => _balance = prevBalance);
    widget.onBalanceChanged(prevBalance);

    final recipientId = recipients.first;
    try {
      await _cpRepository.sendRequest(
        recipientId: recipientId,
        giftId: giftId,
        quantity: _quantity,
        roomId: widget.roomId,
      );
      if (!mounted) return;
      _toast(
        recipients.length > 1
            ? 'تم إرسال طلب الـ CP لأول شخص محدد — في انتظار الرد'
            : 'تم إرسال هدية الـ CP — في انتظار الرد',
      );
    } on CpException catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    }
  }

  Future<void> _sendSingle(String giftId, int recipientId, int prevBalance) async {
    try {
      final result = await widget.repository.send(
        giftId: giftId,
        recipientId: recipientId,
        roomId: widget.roomId,
        quantity: _quantity,
      );
      if (!mounted) return;
      setState(() => _balance = result.senderBalance);
      widget.onBalanceChanged(result.senderBalance);
      _toast('تم إرسال الهدية!');
    } on GiftRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _balance = prevBalance);
      widget.onBalanceChanged(prevBalance);
      _toast(e.message, error: true);
    }
  }

  /// A27 — "الميك الكامل" / "جميع الغرفة" go through ONE request.
  ///
  /// The old client-side loop issued a request per recipient, so a full room
  /// meant up to 30 round trips; the gift-send rate limiter would cut the run
  /// off part-way and the sender was left having paid for an arbitrary prefix
  /// of the list. The server now charges the whole fan-out atomically enough to
  /// report exactly how many landed.
  Future<void> _sendMany(String giftId, List<int> recipients, int prevBalance) async {
    try {
      final result = await widget.repository.sendBatch(
        giftId: giftId,
        recipientIds: recipients,
        roomId: widget.roomId,
        quantity: _quantity,
      );
      if (!mounted) return;
      setState(() => _balance = result.senderBalance);
      widget.onBalanceChanged(result.senderBalance);

      if (result.sent == result.requested) {
        _toast('تم إرسال الهدية إلى ${result.sent} مستلمين');
      } else {
        _toast(
          'تم إرسال ${result.sent} من ${result.requested}'
          '${result.failureMessages.isNotEmpty ? ': ${result.failureMessages.first}' : ''}',
          warning: true,
        );
      }
    } on GiftRepositoryException catch (e) {
      if (!mounted) return;
      // Nothing was charged when the batch is refused up front (the server
      // checks the whole cost before moving a single coin), so the optimistic
      // deduction is simply undone.
      setState(() => _balance = prevBalance);
      widget.onBalanceChanged(prevBalance);
      _toast(e.message, error: true);
    }
  }

  void _toast(String text, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 1),
      backgroundColor: error
          ? Colors.red[700]
          : warning
              ? Colors.orange[800]
              : null,
    ));
  }
}
