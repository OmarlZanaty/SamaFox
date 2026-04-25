import '../models/gift_item.dart';

class GiftCatalog {
  static const List<GiftItem> items = [
    GiftItem(id: 'rose', name: 'وردة', emoji: '🌹', cost: 5),
    GiftItem(id: 'coffee', name: 'قهوة', emoji: '☕', cost: 10),
    GiftItem(id: 'clap', name: 'تصفيق', emoji: '👏', cost: 15),
    GiftItem(id: 'crown', name: 'تاج', emoji: '👑', cost: 50),
    GiftItem(id: 'diamond', name: 'ماسة', emoji: '💎', cost: 100),
    GiftItem(id: 'rocket', name: 'صاروخ', emoji: '🚀', cost: 150),
  ];
}
