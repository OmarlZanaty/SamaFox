import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../repositories/cp_repository.dart';

/// A15 / #44 — the accept/reject prompt for an incoming CP gift.
///
/// Client spec: *"الشخص التاني بيجيله اشعار ان فلان بعتلك هدية CP: قبول / رفض.
/// لو رفض الهديه متتمش ويتخصم منه 30% من قيمة الهديه. لو قبل يتخصم منه سعر
/// الهديه كامل وتتحول قيمتها لتارجت عنده."*
///
/// The 30% is stated on the reject button rather than hidden: the sender is
/// charged for a refusal, so the person refusing should know that, and the
/// person who later asks "why did I lose coins" has seen the rule.
class CpRequestDialog extends StatefulWidget {
  const CpRequestDialog({super.key, required this.request, this.repository});

  final CpRequest request;

  /// Injectable so a test can drive the dialog without a live server.
  final CpRepository? repository;

  /// Shows the prompt. Returns true if accepted, false if rejected, null if the
  /// user dismissed it — dismissing costs nobody anything and leaves the
  /// invitation pending in the notifications list.
  static Future<bool?> show(BuildContext context, CpRequest request) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CpRequestDialog(request: request),
    );
  }

  @override
  State<CpRequestDialog> createState() => _CpRequestDialogState();
}

const _kPink = Color(0xFFFF4081);
const _kCard = Color(0xFF1A0E3E);

class _CpRequestDialogState extends State<CpRequestDialog> {
  late final CpRepository _repo = widget.repository ?? CpRepository();
  bool _busy = false;

  String? _resolve(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  Future<void> _respond({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (accept) {
        await _repo.accept(widget.request.id);
      } else {
        await _repo.reject(widget.request.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(accept);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'تم قبول الـ CP 💞' : 'تم رفض هدية الـ CP'),
        ),
      );
    } on CpException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final avatar = _resolve(r.senderAvatarUrl);
    final giftIcon = _resolve(r.giftIconUrl);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _kPink.withOpacity(0.5)),
        ),
        title: const Row(
          children: [
            Text('💞', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('هدية CP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF2A1A5E),
                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                  child: avatar == null
                      ? Text(
                          r.senderName.isNotEmpty
                              ? r.senderName.characters.first.toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${r.senderName} أرسل لك هدية CP',
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                  ),
                ),
                if (giftIcon != null) ...[
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      giftIcon,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 26)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _line('الهدية', '${r.giftName}${r.quantity > 1 ? ' ×${r.quantity}' : ''}'),
                  const SizedBox(height: 6),
                  _line('القيمة', '${r.totalCoins} كوينز'),
                  if (r.rejectFeeCoins > 0) ...[
                    const SizedBox(height: 6),
                    _line('عند الرفض يُخصم من المُرسل', '${r.rejectFeeCoins} كوينز'),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _respond(accept: false),
            child: const Text('رفض', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPink),
            onPressed: _busy ? null : () => _respond(accept: true),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('قبول', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
