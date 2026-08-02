class InventoryItem {
  final String id;
  final String productId;
  final String name;
  final String type;
  final String previewUrl;
  final String fileUrl;
  final bool isActive;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.type,
    required this.previewUrl,
    required this.fileUrl,
    required this.isActive,
  });

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

    return InventoryItem(
      id: (json['id'] ?? '').toString(),
      productId: (json['product_id'] ?? json['productId'] ?? json['itemId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: normalizedType,
      previewUrl: (json['preview_url'] ?? json['file_url'] ?? json['assetUrl'] ?? '').toString(),
      fileUrl: (json['file_url'] ?? json['preview_url'] ?? json['assetUrl'] ?? '').toString(),
      isActive: isActive,
    );
  }
}
