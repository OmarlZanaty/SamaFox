import 'package:flutter/material.dart';

import '../models/mega_gift_payload.dart';

class MegaGiftOverlay {
  static void show(BuildContext context, MegaGiftPayload payload) {
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Material(
          color: Colors.black.withOpacity(0.82),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'هدية ضخمة!',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _avatar(payload.senderAvatarUrl, payload.senderName),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Image.network(payload.giftImageUrl, width: 72, height: 72),
                          Text(
                            payload.giftNameAr,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          Text(
                            '${payload.coinsValue} كوين',
                            style: const TextStyle(color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                    _avatar(payload.receiverAvatarUrl, payload.receiverName),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'في غرفة: ${payload.roomName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  static Widget _avatar(String url, String name) => Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            child: url.isEmpty ? const Icon(Icons.person) : null,
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      );
}
