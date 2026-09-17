import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The locked-room PIN prompt (enter / set a 5-digit code).
///
/// Extracted from `room_screen.dart`; it has no dependency on the screen.
class PinDialog extends StatefulWidget {
  const PinDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initial,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String? initial;

  @override
  State<PinDialog> createState() => PinDialogState();
}

class PinDialogState extends State<PinDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(v)) {
      setState(() => _error = 'يجب أن يكون 5 أرقام');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.hint,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 5,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                  color: Colors.white, fontSize: 26, letterSpacing: 10),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                errorText: _error,
                hintText: '•••••',
                hintStyle:
                    const TextStyle(color: Colors.white24, letterSpacing: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child:
                const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
