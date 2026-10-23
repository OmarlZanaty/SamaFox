import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/asterion_repository.dart';
import 'asterion_art.dart';

/// أستيريون fairness sheet.
///
/// The help panel says every spin is decided from a seed pair the player can
/// check; this is where they check it. It shows the committed server-seed hash,
/// the client seed they control and the nonce reached so far, and lets them set
/// their own client seed.
///
/// The commitment is the whole point: the hash is published *before* the spins,
/// so the server cannot pick a server seed after seeing the bet.
class AsterionFairnessSheet extends StatefulWidget {
  const AsterionFairnessSheet({super.key, required this.repo, required this.fairness});

  final AsterionRepository repo;
  final AsterionFairness fairness;

  @override
  State<AsterionFairnessSheet> createState() => _AsterionFairnessSheetState();
}

class _AsterionFairnessSheetState extends State<AsterionFairnessSheet> {
  late AsterionFairness _fair = widget.fairness;
  late final TextEditingController _seed = TextEditingController(text: _fair.clientSeed);
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _seed.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final value = _seed.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final updated = await widget.repo.setClientSeed(value);
      if (!mounted) return;
      setState(() {
        _fair = updated;
        _notice = tr('تم حفظ بذرتك', "Your seed was saved");
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = e is AsterionException ? e.message : tr('تعذر حفظ البذرة', "Could not save seed"));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16204A), Color(0xFF070A1B)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                tr('العدالة المُثبتة', "Provably fair"),
                style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('كل جولة تُحسب من بذرة الخادم (المنشور تجزئتها مسبقًا) وبذرتك ورقم الجولة. '
              'غيّر بذرتك متى شئت — النتائج بعدها تعتمد عليها.', "Each round is calculated from the server seed (whose hash is published in advance), your seed and the round number. Change your seed at any time — future results will use it."),
              style: TextStyle(color: AsterionPalette.muted, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 16),
            _field(tr('تجزئة بذرة الخادم', "Server seed hash"), _fair.serverSeedHash, copyable: true),
            _field(tr('بذرتك الحالية', "Your current seed"), _fair.clientSeed, copyable: true),
            _field(tr('رقم الجولة التالية', "Next round number"), '${_fair.nonce}'),
            const SizedBox(height: 10),
            TextField(
              controller: _seed,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: tr('بذرة جديدة', "New seed"),
                labelStyle: const TextStyle(color: AsterionPalette.muted),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AsterionPalette.cyanDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _busy ? null : _apply,
                child: Text(_busy ? '…' : tr('حفظ البذرة', "Save seed")),
              ),
            ),
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Text(
                _notice!,
                style: const TextStyle(color: AsterionPalette.tide, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value, {bool copyable = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AsterionPalette.muted, fontSize: 11.5)),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? '—' : value,
                    textDirection: TextDirection.ltr,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
                if (copyable && value.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 16, color: AsterionPalette.cyan),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('تم النسخ', "Copied")), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      );
}
