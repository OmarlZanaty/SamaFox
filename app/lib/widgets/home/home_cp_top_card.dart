import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/tr.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/cp_repository.dart';
import '../../screens/cp_list_screen.dart';
import '../room/room_cp_top.dart' show CpTopEntry, CpTopUser;
import 'cp_ranking_screen.dart';

final _top = FutureProvider.autoDispose((ref) => loadHomeCp());
final _partner = FutureProvider.autoDispose<CpPartner?>((ref) async {
  final id = ref.watch(authStateProvider.select((s) => s.user?.id));
  if (id == null) return null;
  return CpFeatured.pick(await CpRepository().partners(), null);
});

class HomeCpTopCard extends ConsumerWidget {
  const HomeCpTopCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(_top);
    final entries = top.valueOrNull ?? <HomeCpEntry>[];
    final partner = ref.watch(_partner);
    final me = ref.watch(authStateProvider.select((s) => s.user));
    final p = partner.valueOrNull;
    return Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: Column(children: [
      Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CpRankingScreen(initial: entries))),
        child: Ink(height: 170, padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF3E175D), Color(0xFFA43A80), Color(0xFF492067)]),
            border: Border.all(color: const Color(0xFFECC875), width: 1.5)),
          child: Column(children: [Text(tr('قائمة CP', 'CP Ranking'),
            style: const TextStyle(color: Color(0xFFFFE2A0), fontWeight: FontWeight.bold, fontSize: 17)),
            Expanded(child: top.isLoading && entries.isEmpty ? const Center(child: CircularProgressIndicator())
              : top.hasError && entries.isEmpty ? Center(child: Text(tr('تعذر تحميل القائمة', 'Could not load ranking')))
              : CpPodium(entries: entries))])))),
      if (me != null) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(tr('شريكي', 'My partner')),
        subtitle: Text(partner.isLoading ? tr('جارٍ التحميل', 'Loading') : partner.hasError
          ? tr('تعذر تحميل الشريك — اضغط للمحاولة', 'Could not load partner — tap to retry')
          : p == null ? tr('ليس لديك شريك بعد — أرسل هدية CP لتبدأ', 'No partner yet — send a CP gift to start') : p.name),
        leading: p == null ? const Icon(Icons.favorite_border, color: Colors.pinkAccent)
          : CpPairAvatars(pair: CpTopEntry(rank: 0, level: p.cpLevel ?? 1, levelName: p.cpLevelName,
              a: CpTopUser(id: me.id, name: me.name, avatarUrl: me.avatarUrl),
              b: CpTopUser(id: p.userId, name: p.name, avatarUrl: p.avatarUrl)), size: 30),
        trailing: p == null ? null : Text(p.cpLevelName ?? 'CP Lv.${p.cpLevel ?? 1}'),
        onTap: () async {
          if (partner.hasError) { ref.invalidate(_partner); return; }
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CpListScreen()));
          if (context.mounted) ref.invalidate(_partner);
        }),
    ]));
  }
}
