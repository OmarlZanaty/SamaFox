import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../repositories/olympus_repository.dart';
import 'olympus_strings.dart';

const _gold = Color(0xFFE3B84A);
const _boltBlue = Color(0xFF9FD8FF);
const _violetDeep = Color(0xFF1A0838);
const _violetMid = Color(0xFF2A1258);

/// بوابات أوليمبوس fairness sheet.
///
/// The help panel tells players every round is decided from a seed pair they
/// can check, so this is where they check it: the committed server-seed hash,
/// the client seed they control, and the round number reached.
///
/// The commitment is the point — the hash is published *before* the rounds, so
/// the server cannot pick a server seed after seeing the bet. Rotating reveals
/// the old seed for verification and commits to a fresh one.
class OlympusFairnessSheet extends StatefulWidget {
  const OlympusFairnessSheet({
    super.key,
    required this.repo,
    required this.fairness,
    required this.strings,
  });

  final OlympusRepository repo;
  final OlympusFairness fairness;
  final OlympusStrings strings;

  @override
  State<OlympusFairnessSheet> createState() => _OlympusFairnessSheetState();
}

class _OlympusFairnessSheetState extends State<OlympusFairnessSheet> {
  late OlympusFairness _fair = widget.fairness;
  late final TextEditingController _seed =
      TextEditingController(text: _fair.clientSeed);

  bool _busy = false;
  String? _notice;
  String? _revealed;

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
        _notice = widget.strings.seedSaved;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = e is OlympusException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await widget.repo.rotateServerSeed(clientSeed: _fair.clientSeed);
      if (!mounted) return;
      setState(() {
        _revealed = result.revealedServerSeed;
        _fair = result.fairness;
        _seed.text = result.fairness.clientSeed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = e is OlympusException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    setState(() => _notice = widget.strings.copied);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Directionality(
      textDirection: s.direction,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_violetMid, _violetDeep],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: _gold, width: 1.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                s.fairness,
                style: const TextStyle(
                  color: _gold,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.fairnessBody,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 18),

              _readOnly(s.serverSeedHash, _fair.serverSeedHash),
              const SizedBox(height: 12),
              _readOnly(s.nonce, '${_fair.nonce}'),
              const SizedBox(height: 12),

              Text(
                s.clientSeed,
                style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seed,
                      enabled: !_busy,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _boltBlue),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _gold),
                    onPressed: _busy ? null : _apply,
                    child: Text(
                      s.saveSeed,
                      style: const TextStyle(
                        color: Color(0xFF2B1206),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              if (_revealed != null) ...[
                const SizedBox(height: 14),
                _readOnly(s.revealedSeed, _revealed!, highlight: true),
              ],

              if (_notice != null) ...[
                const SizedBox(height: 12),
                Text(
                  _notice!,
                  style: const TextStyle(color: _boltBlue, fontSize: 12),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _gold.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _busy ? null : _rotate,
                  icon: const Icon(Icons.autorenew_rounded, color: _gold, size: 18),
                  label: Text(
                    s.rotateSeed,
                    style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readOnly(String label, String value, {bool highlight = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _copy(value),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: highlight ? _gold : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      textDirection: TextDirection.ltr,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlight ? _gold : Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_rounded, color: Colors.white38, size: 15),
                ],
              ),
            ),
          ),
        ],
      );
}
