import '../../services/socket_service.dart';
import '../app_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/tr.dart';

class MicQueuePanel extends StatelessWidget {
  final List<int> queueUserIds;
  final List<RoomParticipant> entries;
  final bool isAdmin;
  final int? myUserId;
  final VoidCallback onRequest;
  final VoidCallback onCancel;
  final void Function(int userId) onApprove;
  final void Function(int userId) onReject;

  const MicQueuePanel({
    super.key,
    required this.queueUserIds,
    this.entries = const [],
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
          Text(
            tr('طلبات فتح المابك', 'Mic requests'),
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
                      label: Text(tr('طلب فتح المايك', 'Request mic')),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                      label: Text(tr('رفض', 'Decline')),
                    ),
                  ),
              ],
            ),
          if (queueUserIds.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(tr('لا يوجد طلب فتح المايك.', 'No mic requests.'),
                  style: TextStyle(color: Colors.white70)),
            )
          else
            ...queueUserIds.map((uid) {
              final matches = entries.where((entry) => entry.userId == uid);
              final entry = matches.isEmpty ? null : matches.first;
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (entry?.avatar ?? '').isNotEmpty
                      ? appImage(entry!.avatar!, 40) : null,
                  child: (entry?.avatar ?? '').isEmpty ? const Icon(Icons.person) : null,
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text((entry?.name.isNotEmpty ?? false) ? entry!.name : tr('مستخدم #$uid', 'User #$uid'),
                    style: const TextStyle(color: Colors.white)),
                trailing: isAdmin
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('قبول', 'Approve'),
                      onPressed: () => onApprove(uid),
                      icon: const Icon(Icons.check_circle,
                          color: Colors.green),
                    ),
                    IconButton(
                      tooltip: tr('رفض', 'Reject'),
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
