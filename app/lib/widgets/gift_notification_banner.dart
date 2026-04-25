import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/app_config.dart';
import '../models/gift_event.dart';

class GiftNotificationBanner extends StatelessWidget {
  final GiftEvent event;

  const GiftNotificationBanner({required this.event, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          _avatar(event.senderAvatarUrl),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.senderName,
              style: _nameStyle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 32, height: 32, child: _giftMedia(event.giftImageUrl)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, color: Colors.amber, size: 16),
          ),
          _avatar(event.receiverAvatarUrl),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.receiverName,
              style: _nameStyle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url) => CircleAvatar(
        radius: 16,
        backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
        child: (url == null || url.isEmpty) ? const Icon(Icons.person, size: 16) : null,
      );

  TextStyle _nameStyle() =>
      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500);

  Widget _giftMedia(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return const Icon(Icons.card_giftcard, color: Colors.amber, size: 22);

    if (_isEmojiLike(raw)) {
      return Center(child: Text(raw, style: const TextStyle(fontSize: 20)));
    }

    if (raw.startsWith('assets/')) {
      if (raw.toLowerCase().endsWith('.svg')) {
        return SvgPicture.asset(raw, fit: BoxFit.contain);
      }
      return Image.asset(raw, fit: BoxFit.contain);
    }

    final url = raw.startsWith('/') ? '${AppConfig.apiBaseUrl}$raw' : raw;
    if (url.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        url,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      );
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return const Icon(Icons.card_giftcard, color: Colors.amber, size: 22);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) =>
          const Icon(Icons.card_giftcard, color: Colors.amber, size: 22),
    );
  }

  bool _isEmojiLike(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        value.contains('/') ||
        value.contains('.png') ||
        value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.webp') ||
        value.contains('.gif') ||
        value.contains('.svg')) {
      return false;
    }
    return value.runes.length <= 6;
  }
}
