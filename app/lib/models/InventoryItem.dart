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
    String rawType = json['type'];

    String normalizedType;

    switch (rawType) {
      case "ENTRANCE_EFFECT":
        normalizedType = "seat_effect";
        break;
      case "PROFILE_FRAME":
        normalizedType = "avatar_frame";
        break;
      default:
        normalizedType = rawType;
    }

    return InventoryItem(
      id: json['id'],
      productId: json['product_id'],
      name: json['name'],
      type: normalizedType,
      previewUrl: json['preview_url'] ?? json['file_url'],
      fileUrl: json['file_url'] ?? json['preview_url'],
      isActive: json['is_active'],
    );
  }
}