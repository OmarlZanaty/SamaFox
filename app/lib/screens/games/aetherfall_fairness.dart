import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/aetherfall_repository.dart';

const _cyan = Color(0xFF4DD8E6);
const _bgTop = Color(0xFF0F1638);
const _mint = Color(0xFF7CE8B0);

/// أثيرفول fairness sheet.
///
/// The help panel tells players every spin is decided from a seed pair they can
/// check, so this is where they check it. Shows the committed server-seed hash,
/// the client seed they control, and the nonce that has been reached, and lets
/// them set their own client seed.
///
/// The commitment is the point: the hash is published *before* the spins, so the
/// server cannot pick a server seed after seeing the bet. Rotating reveals the
/// old seed for verification and commits to a fresh one.
class AetherfallFairnessSheet extends StatefulWidget {
  const AetherfallFairnessSheet({
    super.key,
    required this.repo,
    required this.fairness,
  });

  final AetherfallRepository repo;
  final AetherfallFairness fairness;

  @override
  State<AetherfallFairnessSheet> createState() => _AetherfallFairnessSheetState();
}

class _AetherfallFairnessSheetState extends State<AetherfallFairnessSheet> {
  late AetherfallFairness _fair = widget.fairness;
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
        _notice = 'تم حفظ بذرتك';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = e is AetherfallException ? e.message : 'تعذر حفظ البذرة';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _bgTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: const Text(
                'عدالة مثبتة',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'كل جولة يحسمها الخادم من ثلاث قيم: بذرة سرية عنده، وبذرة تخصّك أنت، '
              'ورقم جولة يزيد واحدًا في كل مرة. الخادم ينشر بصمة بذرته قبل أن تلعب، '
              'فلا يستطيع تغييرها بعد أن يرى رهانك. وتستطيع تغيير بذرتك متى شئت، '
              'فتتغير النتائج معها.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 18),
            _field('بصمة بذرة الخادم (معلنة مسبقًا)', _fair.serverSeedHash, copyable: true),
            _field('بذرتك', _fair.clientSeed, copyable: true),
            _field('رقم الجولة على هذا الزوج', '${_fair.nonce}'),
            const SizedBox(height: 14),
            const Text(
              'غيّر بذرتك',
              style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: 'بذرتك',
                    child: TextField(
                      controller: _seed,
                      maxLength: 64,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'حفظ البذرة',
                  child: ElevatedButton(
                    onPressed: _busy ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cyan,
                      foregroundColor: const Color(0xFF07030F),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ'),
                  ),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Text(
                _notice!,
                style: const TextStyle(color: _mint, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value, {bool copyable = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: label,
                    value: value,
                    child: SelectableText(
                      value.isEmpty ? '—' : value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                if (copyable)
                  Semantics(
                    button: true,
                    label: 'نسخ $label',
                    child: IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white38),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}
