import 'package:flutter/material.dart';

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
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(event.senderAvatarUrl),
          const SizedBox(width: 8),
          Text(event.senderName, style: _nameStyle()),
          const SizedBox(width: 8),
          Image.network(event.giftImageUrl, width: 32, height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, color: Colors.amber, size: 16),
          ),
          _avatar(event.receiverAvatarUrl),
          const SizedBox(width: 8),
          Text(event.receiverName, style: _nameStyle()),
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
}
