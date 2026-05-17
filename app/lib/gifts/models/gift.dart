import 'package:flutter/foundation.dart';

enum GiftFormat { svgCss, video }

extension GiftFormatX on GiftFormat {
  String get wire => this == GiftFormat.svgCss ? 'SVG_CSS' : 'VIDEO';
  static GiftFormat parse(String? raw) {
    switch (raw) {
      case 'VIDEO':
        return GiftFormat.video;
      case 'SVG_CSS':
      default:
        return GiftFormat.svgCss;
    }
  }
}

enum GiftTier { small, medium, large, legendary }

extension GiftTierX on GiftTier {
  String get wire {
    switch (this) {
      case GiftTier.small:
        return 'SMALL';
      case GiftTier.medium:
        return 'MEDIUM';
      case GiftTier.large:
        return 'LARGE';
      case GiftTier.legendary:
        return 'LEGENDARY';
    }
  }

  static GiftTier parse(String? raw) {
    switch (raw) {
      case 'LEGENDARY':
        return GiftTier.legendary;
      case 'LARGE':
        return GiftTier.large;
      case 'MEDIUM':
        return GiftTier.medium;
      case 'SMALL':
      default:
        return GiftTier.small;
    }
  }
}

@immutable
class Gift {
  final String id;
  final String name;
  final String? nameAr;
  final String iconUrl;
  final GiftFormat format;
  final String? animationHtml;
  final String? animationUrl;
  final bool videoHasAlpha;
  final bool fireworksEnabled;
  final List<String> fireworksColors;
  final int coinCost;
  final GiftTier tier;
  final int animationMs;
  final bool isComboEligible;
  final bool broadcastGlobal;
  final String? category;
  final int sortOrder;

  const Gift({
    required this.id,
    required this.name,
    this.nameAr,
    required this.iconUrl,
    required this.format,
    this.animationHtml,
    this.animationUrl,
    this.videoHasAlpha = false,
    this.fireworksEnabled = false,
    this.fireworksColors = const [],
    required this.coinCost,
    required this.tier,
    required this.animationMs,
    this.isComboEligible = true,
    this.broadcastGlobal = false,
    this.category,
    this.sortOrder = 0,
  });

  factory Gift.fromJson(Map<String, dynamic> json) {
    final colors = json['fireworksColors'];
    return Gift(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      nameAr: json['nameAr'] as String?,
      iconUrl: json['iconUrl'] as String? ?? '',
      format: GiftFormatX.parse(json['format'] as String?),
      animationHtml: json['animationHtml'] as String?,
      animationUrl: json['animationUrl'] as String?,
      videoHasAlpha: json['videoHasAlpha'] as bool? ?? false,
      fireworksEnabled: json['fireworksEnabled'] as bool? ?? false,
      fireworksColors: colors is List
          ? colors.map((c) => c.toString()).toList()
          : const [],
      coinCost: (json['coinCost'] as num?)?.toInt() ?? 0,
      tier: GiftTierX.parse(json['tier'] as String?),
      animationMs: (json['animationMs'] as num?)?.toInt() ?? 3000,
      isComboEligible: json['isComboEligible'] as bool? ?? true,
      broadcastGlobal: json['broadcastGlobal'] as bool? ?? false,
      category: json['category'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class GiftUser {
  final int id;
  final String name;
  final String? avatarUrl;
  const GiftUser({required this.id, required this.name, this.avatarUrl});

  factory GiftUser.fromJson(Map<String, dynamic> json) => GiftUser(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
      );
}

@immutable
class GiftSendEvent {
  final String transactionId;
  final int senderId;
  final int recipientId;
  final int? roomId;
  final int quantity;
  final int totalCoins;
  final String? comboKey;
  final int comboCount;
  final bool broadcast;
  final GiftUser? sender;
  final GiftUser? recipient;
  final Gift gift;
  final DateTime ts;

  const GiftSendEvent({
    required this.transactionId,
    required this.senderId,
    required this.recipientId,
    this.roomId,
    required this.quantity,
    required this.totalCoins,
    this.comboKey,
    required this.comboCount,
    required this.broadcast,
    this.sender,
    this.recipient,
    required this.gift,
    required this.ts,
  });

  factory GiftSendEvent.fromJson(Map<String, dynamic> json) {
    // Socket.IO delivers nested objects as Map<dynamic, dynamic> — normalize them.
    Map<String, dynamic>? _asMap(Object? raw) =>
        raw is Map ? Map<String, dynamic>.from(raw) : null;
    final giftMap = _asMap(json['gift']);
    if (giftMap == null) {
      throw const FormatException('gift_sent event missing gift field');
    }
    return GiftSendEvent(
      transactionId: json['transactionId'] as String,
      senderId: (json['senderId'] as num).toInt(),
      recipientId: (json['recipientId'] as num).toInt(),
      roomId: (json['roomId'] as num?)?.toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      totalCoins: (json['totalCoins'] as num?)?.toInt() ?? 0,
      comboKey: json['comboKey'] as String?,
      comboCount: (json['comboCount'] as num?)?.toInt() ?? 1,
      broadcast: json['broadcast'] as bool? ?? false,
      sender: _asMap(json['sender']) is Map<String, dynamic>
          ? GiftUser.fromJson(_asMap(json['sender'])!)
          : null,
      recipient: _asMap(json['recipient']) is Map<String, dynamic>
          ? GiftUser.fromJson(_asMap(json['recipient'])!)
          : null,
      gift: Gift.fromJson(giftMap),
      ts: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

@immutable
class GiftCatalog {
  final int version;
  final Map<GiftTier, List<Gift>> byTier;

  const GiftCatalog({required this.version, required this.byTier});

  List<Gift> get all => GiftTier.values.expand<Gift>((t) => byTier[t] ?? const <Gift>[]).toList();

  factory GiftCatalog.fromJson(Map<String, dynamic> json) {
    final raw = (json['gifts'] as Map<String, dynamic>?) ?? const {};
    GiftTier toTier(String k) => GiftTierX.parse(k);
    return GiftCatalog(
      version: (json['version'] as num?)?.toInt() ?? 1,
      byTier: {
        for (final entry in raw.entries)
          toTier(entry.key): (entry.value as List)
              .map((e) => Gift.fromJson(e as Map<String, dynamic>))
              .toList(),
      },
    );
  }
}

@immutable
class SmallGiftItem {
  final String id;
  final Gift gift;
  final GiftUser? sender;
  final DateTime addedAt;
  const SmallGiftItem({
    required this.id,
    required this.gift,
    this.sender,
    required this.addedAt,
  });
}
