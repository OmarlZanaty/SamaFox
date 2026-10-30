import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../services/dio_client.dart';
import '../../screens/profile_screen.dart';
import '../app_network_image.dart';
import '../room/room_cp_top.dart' show CpTopEntry, CpTopUser;

class HomeCpEntry {
  HomeCpEntry(this.json) : pair = CpTopEntry.fromJson(json);
  final Map<String, dynamic> json;
  final CpTopEntry pair;
  String get points => '${json['cpXp'] ?? json['points'] ?? 0}';
}

Future<List<HomeCpEntry>> loadHomeCp() async {
  final response = await DioClient.dio.get('/cp/top', queryParameters: {'limit': 30});
  return (response.data['data'] as List).whereType<Map>()
      .map((e) => HomeCpEntry(Map<String, dynamic>.from(e))).toList();
}

void openCpUser(BuildContext context, CpTopUser user) {
  if (user.id <= 0) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ProfileScreen(userId: user.id, source: 'home')));
}

class CpPairAvatars extends StatelessWidget {
  const CpPairAvatars({super.key, required this.pair, this.size = 40, this.interactive = false});
  final CpTopEntry pair;
  final double size;
  final bool interactive;
  @override
  Widget build(BuildContext context) => SizedBox(width: size * 1.7, height: size,
    child: Stack(children: [
      for (final item in [(pair.a, 0.0), (pair.b, size * .7)])
        Positioned(left: item.$2, child: GestureDetector(
          onTap: interactive ? () => openCpUser(context, item.$1) : null,
          child: Container(width: size, height: size, padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF4D486)),
            child: ClipOval(child: item.$1.avatarUrl?.isNotEmpty == true
              ? AppNetworkImage(item.$1.avatarUrl!, width: size, height: size, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person))
              : const ColoredBox(color: Color(0xFF713B85), child: Icon(Icons.person, color: Colors.white)))))),
      Positioned(left: size * .68, top: size * .55,
        child: Icon(Icons.favorite, size: size * .35, color: const Color(0xFFFF72B1))),
    ]));
}

class CpLevelBadge extends StatelessWidget {
  const CpLevelBadge({super.key, required this.pair});
  final CpTopEntry pair;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFF763D85), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFF4D486))),
    child: Text(pair.levelName?.isNotEmpty == true ? pair.levelName! : 'CP Lv.${pair.level}',
      maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xFFFFE6A8), fontSize: 10)));
}

class CpPodium extends StatelessWidget {
  const CpPodium({super.key, required this.entries, this.interactive = false});
  final List<HomeCpEntry> entries;
  final bool interactive;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return Center(child: Text(tr('لا يوجد ثنائيات بعد', 'No couples yet'),
      style: const TextStyle(color: Colors.white70)));
    return Row(textDirection: TextDirection.ltr, crossAxisAlignment: CrossAxisAlignment.end,
      children: [for (final index in [2, 0, 1]) Expanded(child: index >= entries.length
        ? const SizedBox() : _place(context, entries[index].pair, index + 1))]);
  }
  Widget _place(BuildContext context, CpTopEntry pair, int rank) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(rank == 1 ? '♛ 1' : '#$rank', style: TextStyle(color: const Color(0xFFFFDA85), fontSize: rank == 1 ? 19 : 12)),
      CpPairAvatars(pair: pair, size: rank == 1 ? 44 : 34, interactive: interactive),
      const SizedBox(height: 3),
      for (final user in [pair.a, pair.b]) GestureDetector(
        onTap: interactive ? () => openCpUser(context, user) : null,
        child: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 10))),
      CpLevelBadge(pair: pair),
    ]));
}

class CpRankingScreen extends StatefulWidget {
  const CpRankingScreen({super.key, required this.initial});
  final List<HomeCpEntry> initial;
  @override
  State<CpRankingScreen> createState() => _CpRankingScreenState();
}
class _CpRankingScreenState extends State<CpRankingScreen> {
  late List<HomeCpEntry> entries = widget.initial;
  Future<void> refresh() async {
    try {
      final next = await loadHomeCp();
      if (mounted) setState(() => entries = next);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('تعذر تحميل القائمة', 'Could not load ranking'))));
    }
  }
  @override
  void initState() { super.initState(); refresh(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF210D35),
    appBar: AppBar(title: Text(tr('قائمة CP', 'CP Ranking')), backgroundColor: const Color(0xFF58235F)),
    body: RefreshIndicator(onRefresh: refresh, child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
      itemCount: 1 + (entries.length > 3 ? entries.length - 3 : 0),
      itemBuilder: (context, index) {
        if (index == 0) return SizedBox(height: 180, child: CpPodium(entries: entries, interactive: true));
        final entry = entries[index + 2];
        final pair = entry.pair;
        return Card(color: const Color(0xFF48224F), child: Padding(
          padding: const EdgeInsets.all(10), child: Row(children: [
            Text('${index + 3}', style: const TextStyle(color: Color(0xFFFFDA85))),
            const SizedBox(width: 8), CpPairAvatars(pair: pair, size: 32, interactive: true),
            const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final user in [pair.a, pair.b]) InkWell(
                onTap: () => openCpUser(context, user), child: Text(user.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)))])),
            Flexible(child: Column(children: [CpLevelBadge(pair: pair),
              Text('${entry.points} CP', style: const TextStyle(color: Colors.white70, fontSize: 11))])),
          ])));
      })));
}
