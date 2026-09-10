import 'package:flutter/material.dart';

import '../repositories/cp_repository.dart';
import '../screens/cp_list_screen.dart';

/// C17 — the CP box.
///
/// A decorated entry point ("في مربع مزخرف علي ذوقك") that opens the list of
/// everyone the user has a CP with. The count is loaded lazily and the box is
/// still shown at zero, because it is also how someone discovers the feature
/// exists — hiding it until you already have a CP would be backwards.
///
/// 2026-09-10: moved off the rooms page. The client's placement is the
/// PROFILE page, immediately above the gifts the user has received —
/// "مكانه الصفحه الشخصيه فوق الهدايا الممنوحه للمستخدم بالظبط" — so this
/// lives in widgets/ now instead of being private to home_screen.
class CpBox extends StatefulWidget {
  const CpBox({super.key});

  @override
  State<CpBox> createState() => CpBoxState();
}

class CpBoxState extends State<CpBox> {
  late Future<List<CpPartner>> _future;

  @override
  void initState() {
    super.initState();
    _future = CpRepository().partners();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CpListScreen()),
          );
          // Coming back from a cancellation must not leave a stale count.
          if (mounted) setState(() => _future = CpRepository().partners());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A1250), Color(0xFF7A1D4E)],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x66FF4081)),
            boxShadow: const [
              BoxShadow(color: Color(0x33FF4081), blurRadius: 14, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              const Text('💞', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Text(
                'CP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              FutureBuilder<List<CpPartner>>(
                future: _future,
                builder: (context, snap) {
                  // A failed load shows no chip rather than an error: the box
                  // still opens, and the list screen reports the failure itself.
                  if (!snap.hasData) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${snap.data!.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              const Icon(Icons.chevron_left, color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
