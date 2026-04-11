import 'package:flutter/material.dart';

class MicQueuePanel extends StatelessWidget {
  final List<int> queueUserIds;
  final bool isAdmin;
  final int? myUserId;
  final VoidCallback onRequest;
  final VoidCallback onCancel;
  final void Function(int userId) onApprove;
  final void Function(int userId) onReject;

  const MicQueuePanel({
    super.key,
    required this.queueUserIds,
    required this.isAdmin,
    required this.myUserId,
    required this.onRequest,
    required this.onCancel,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final inQueue =
        myUserId != null && queueUserIds.contains(myUserId ?? -1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'طلبات فتح المابك',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!isAdmin) // Only guests see this row
            Row(
              children: [
                if (!inQueue)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onRequest,
                      icon: const Icon(Icons.pan_tool),
                      label: const Text('طلب فتح المايك'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                    ),
                  ),
              ],
            ),
          if (queueUserIds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('لا يوجد طلب فتح المايك.',
                  style: TextStyle(color: Colors.white70)),
            )
          else
            ...queueUserIds.map((uid) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('مستخدم #$uid',
                    style: const TextStyle(color: Colors.white)),
                trailing: isAdmin
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => onApprove(uid),
                      icon: const Icon(Icons.check_circle,
                          color: Colors.green),
                    ),
                    IconButton(
                      onPressed: () => onReject(uid),
                      icon:
                      const Icon(Icons.cancel, color: Colors.red),
                    ),
                  ],
                )
                    : null,
              );
            }).toList(),
        ],
      ),
    );
  }
}
