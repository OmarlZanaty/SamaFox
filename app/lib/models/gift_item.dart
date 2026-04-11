class GiftItem {
  final String id; // e.g. "rose"
  final String name; // e.g. "Rose"
  final String emoji; // e.g. "🌹"
  final int cost; // coins

  const GiftItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.cost,
  });
}
