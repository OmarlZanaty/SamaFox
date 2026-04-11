import '../models/gift_item.dart';

class GiftCatalog {
  static const List<GiftItem> items = [
    GiftItem(id: 'rose', name: 'Rose', emoji: '🌹', cost: 5),
    GiftItem(id: 'coffee', name: 'Coffee', emoji: '☕', cost: 10),
    GiftItem(id: 'clap', name: 'Clap', emoji: '👏', cost: 15),
    GiftItem(id: 'crown', name: 'Crown', emoji: '👑', cost: 50),
    GiftItem(id: 'diamond', name: 'Diamond', emoji: '💎', cost: 100),
    GiftItem(id: 'rocket', name: 'Rocket', emoji: '🚀', cost: 150),
  ];
}
