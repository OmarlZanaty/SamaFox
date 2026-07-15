class Product {
  final String id;
  final String name;
  final String type;
  final int priceCoins;
  final String fileUrl;
  final String previewUrl;

  Product({
    required this.id,
    required this.name,
    required this.type,
    required this.priceCoins,
    required this.fileUrl,
    required this.previewUrl,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    String normalizeType(String? type) {
      if (type == "ENTRANCE_EFFECT") return "seat_effect";
      if (type == "PROFILE_FRAME") return "avatar_frame";
      if (type == "FRAME") return "avatar_frame";
      if (type == "ENTRANCE_BANNER") return "entrance";
      if (type == "BADGE") return "badge";
      return type ?? "";
    }

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? "",
      type: normalizeType(json['type']),
      priceCoins: json['price_coins'] ?? 0,
      fileUrl: json['file_url'] ?? "",
      previewUrl: json['preview_url'] ?? json['file_url'] ?? "", // ✅ FIX
    );
  }
}
