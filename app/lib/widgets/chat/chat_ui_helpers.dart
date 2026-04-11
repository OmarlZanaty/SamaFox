import 'package:flutter/material.dart';

String shortTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  } catch (_) {
    return '';
  }
}

enum ReceiptStatus { sending, sent, delivered, read }

ReceiptStatus receiptFor({
  required bool isMe,
  required String? deliveredAt,
  required String? readAt,
  required bool localSending,
}) {
  if (!isMe) return ReceiptStatus.sent;
  if (localSending) return ReceiptStatus.sending;
  if (readAt != null && readAt.isNotEmpty) return ReceiptStatus.read;
  if (deliveredAt != null && deliveredAt.isNotEmpty) return ReceiptStatus.delivered;
  return ReceiptStatus.sent;
}

Widget receiptIcon(ReceiptStatus s, {required Color color}) {
  // Simple WhatsApp-like.
  switch (s) {
    case ReceiptStatus.sending:
      return Icon(Icons.access_time, size: 14, color: color.withOpacity(0.8));
    case ReceiptStatus.sent:
      return Icon(Icons.check, size: 14, color: color.withOpacity(0.8));
    case ReceiptStatus.delivered:
      return Icon(Icons.done_all, size: 14, color: color.withOpacity(0.8));
    case ReceiptStatus.read:
      return Icon(Icons.done_all, size: 14, color: color); // you can color blue later if you want
  }
}