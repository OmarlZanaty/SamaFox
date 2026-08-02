class InventoryItem {
  final String id;
  final String productId;
  final String name;
  final String type;
  final String previewUrl;
  final String fileUrl;
  final bool isActive;

  /// When this item stops being owned. null = أبدي (permanent), which is every
  /// item bought before products gained durations.
  final DateTime? expiresAt;

  /// The term the product was sold with, in days. null = permanent.
  final int? durationDays;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.type,
    required this.previewUrl,
    required this.fileUrl,
    required this.isActive,
    this.expiresAt,
    this.durationDays,
  });

  /// Whole days left, rounded up, or null when the item never expires.
  /// 0 means it lapses today.
  int? get daysRemaining {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inMinutes / (60 * 24)).ceil();
  }

  bool get isPermanent => expiresAt == null;

  /// Short label for the badge on the item card: «أبدي» or «متبقي ٥ أيام».
  String get remainingLabel {
    final d = daysRemaining;
    if (d == null) return 'أبدي';
    if (d <= 0) return 'انتهت';
    if (d == 1) return 'متبقي يوم';
    if (d == 2) return 'متبقي يومان';
    if (d <= 10) return 'متبقي $d أيام';
    return 'متبقي $d يوم';
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['itemType'] ?? '').toString();

    String normalizedType;

    switch (rawType) {
      case "ENTRANCE_EFFECT":
      case "SEAT_EFFECT":
      case "seat_effect":
        normalizedType = "seat_effect";
        break;
      case "PROFILE_FRAME":
      case "FRAME":
      case "AVATAR_FRAME":
      case "avatar_frame":
        normalizedType = "avatar_frame";
        break;
      case "ENTRANCE_BANNER":
      case "entrance":
        normalizedType = "entrance";
        break;
      case "BADGE":
      case "badge":
        normalizedType = "badge";
        break;
      case "CHAT_BUBBLE":
      case "chat_bubble":
        normalizedType = "chat_bubble";
        break;
      case "CHAT_TOP_BANNER":
      case "chat_top_banner":
        normalizedType = "chat_top_banner";
        break;
      default:
        normalizedType = rawType;
    }

    final dynamic activeRaw = json['is_active'] ?? json['isActive'] ?? json['active'] ?? false;
    final bool isActive = activeRaw == true || activeRaw.toString() == '1' || activeRaw.toString().toLowerCase() == 'true';

    final rawExpiry = json['expires_at'] ?? json['expiresAt'];
    final expiresAt = rawExpiry == null ? null : DateTime.tryParse(rawExpiry.toString());
    final rawDuration = json['duration_days'] ?? json['durationDays'];
    final durationDays = rawDuration is int
        ? rawDuration
        : int.tryParse(rawDuration?.toString() ?? '');

    return InventoryItem(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? json['productId'] ?? json['itemId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: normalizedType,
      previewUrl: (json['preview_url'] ?? json['file_url'] ?? json['assetUrl'] ?? '').toString(),
      fileUrl: (json['file_url'] ?? json['preview_url'] ?? json['assetUrl'] ?? '').toString(),
      isActive: isActive,
      expiresAt: expiresAt,
      durationDays: durationDays,
    );
  }
}
