import 'package:flutter/material.dart';

import '../../config/app_config.dart';
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
  static const List<int> _kQuantities = [1, 7, 10, 20, 50];
  int _quantity = _kQuantities.first;
  int _selectedGiftCost = 0; // coin cost of the currently selected gift (for optimistic deduction)
  bool _sending = false;
  late Set<int> _selectedRecipientIds;
  _RecipientScope _scope = _RecipientScope.allRoom;

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
    final categories = catalog.all.map((g) => g.category ?? '').where((c) => c.isNotEmpty).toSet().toList();
    final keys = ['all', ...categories];
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
                tabs: _tabKeys.map((k) => Tab(text: k == 'all' ? 'عادي' : k)).toList(),
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

  void _showScopeMenu() async {
    final selected = await showMenu<_RecipientScope>(
      context: context,
      position: const RelativeRect.fromLTRB(24, 90, 0, 0),
      color: _kCardColor,
      items: const [
        PopupMenuItem(value: _RecipientScope.allRoom, child: Text('جميع الغرف', style: TextStyle(color: Colors.white))),
        PopupMenuItem(value: _RecipientScope.micOnly, child: Text('الميك الكامل', style: TextStyle(color: Colors.white))),
      ],
    );
    if (selected != null && selected != _scope) {
      setState(() {
        _scope = selected;
        final valid = _scopedRecipients.map((r) => r.id).toSet();
        _selectedRecipientIds.removeWhere((id) => !valid.contains(id));
        if (_selectedRecipientIds.isEmpty && _scopedRecipients.isNotEmpty) {
          _selectedRecipientIds.add(_scopedRecipients.first.id);
        }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _showScopeMenu,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _scope == _RecipientScope.allRoom ? 'جميع الغرف' : 'الميك الكامل',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.close, color: Colors.white54, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (recipients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('لا يوجد مستلمون', style: TextStyle(color: Colors.white60))),
            )
          else
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recipients.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _recipientChip(recipients[i]),
              ),
            ),
        ],
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
        width: 60,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _kGoldColor : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [const BoxShadow(color: _kGoldColor, blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: avatarUrl != null
                    ? Image.network(avatarUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(r.name))
                    : _avatarFallback(r.name),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              r.seatNumber != null ? '${r.seatNumber}' : r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _kGoldColor : Colors.white70,
                fontSize: 11,
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
      position: const RelativeRect.fromLTRB(200, 400, 0, 0),
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
                  const Text('إعادة الشحن', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(width: 8),
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
    final int prevBalance = _balance;
    final int optimisticCost = _selectedGiftCost * _quantity * recipients.length;
    setState(() {
      _sending = true;
      _balance = (_balance - optimisticCost).clamp(0, 1 << 62);
    });
    widget.onBalanceChanged(_balance);
    int successCount = 0;
    GiftSendResult? lastResult;
    String? firstErrorMessage;
    try {
      for (final rid in recipients) {
        try {
          final result = await widget.repository.send(
            giftId: giftId,
            recipientId: rid,
            roomId: widget.roomId,
            quantity: _quantity,
          );
          lastResult = result;
          successCount++;
        } on GiftRepositoryException catch (e) {
          firstErrorMessage ??= e.message;
          if (e.code == 'INSUFFICIENT_BALANCE' || e.code == 'RATE_LIMIT' || e.code == 'UNAUTHORIZED') {
            break;
          }
        }
      }
      if (lastResult != null) {
        // Server authoritative balance wins over the optimistic guess.
        setState(() => _balance = lastResult!.senderBalance);
        widget.onBalanceChanged(lastResult.senderBalance);
      } else {
        // Nothing sent — undo the optimistic deduction.
        setState(() => _balance = prevBalance);
        widget.onBalanceChanged(prevBalance);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (successCount > 0 && firstErrorMessage == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(successCount > 1 ? 'تم إرسال الهدية إلى $successCount مستلمين' : 'تم إرسال الهدية!'),
          duration: const Duration(seconds: 1),
        ));
      } else if (successCount > 0 && firstErrorMessage != null) {
        messenger.showSnackBar(SnackBar(
          content: Text('تم إرسال $successCount من ${recipients.length}: $firstErrorMessage'),
          backgroundColor: Colors.orange[800],
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(firstErrorMessage ?? 'فشل إرسال الهدية'),
          backgroundColor: Colors.red[700],
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
