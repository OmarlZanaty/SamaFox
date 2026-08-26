class Product {
  final String id;
  final String name;
  final String type;
  final int priceCoins;
  final String fileUrl;
  final String previewUrl;

  /// How long the item stays equipped after buying, in days.
  /// null = أبدي (permanent) — the same meaning the backend gives it.
  final int? durationDays;

  Product({
    required this.id,
    required this.name,
    required this.type,
    required this.priceCoins,
    required this.fileUrl,
    required this.previewUrl,
    this.durationDays,
  });

  /// Ready-to-show term label, worded like the VIP sheet so the store reads
  /// the same as the rest of the app.
  String get durationLabel =>
      durationDays == null ? 'أبدي' : '$durationDays يوم';

  factory Product.fromJson(Map<String, dynamic> json) {
    String normalizeType(String? type) {
      if (type == "ENTRANCE_EFFECT") return "seat_effect";
      if (type == "PROFILE_FRAME") return "avatar_frame";
      if (type == "FRAME") return "avatar_frame";
      if (type == "ENTRANCE_BANNER") return "entrance";
      if (type == "BADGE") return "badge";
      if (type == "CHAT_BUBBLE") return "chat_bubble";
      if (type == "CHAT_TOP_BANNER") return "chat_top_banner";
      // B2/B3 — خلفية الصفحة الشخصية and إطار تزيين الصفحة الشخصية. Missing
      // here, the raw server type reached the store's tab filter and matched no
      // tab, so products of both kinds were created in لوحة التحكم and never
      // appeared in the app.
      if (type == "PROFILE_BACKGROUND") return "profile_background";
      if (type == "PROFILE_DECOR") return "profile_decor";
      return type ?? "";
    }

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? "",
      type: normalizeType(json['type']),
      priceCoins: json['price_coins'] ?? 0,
      fileUrl: json['file_url'] ?? "",
      previewUrl: json['preview_url'] ?? json['file_url'] ?? "", // ✅ FIX
      durationDays: (json['duration_days'] as num?)?.toInt(),
    );
  }
}
