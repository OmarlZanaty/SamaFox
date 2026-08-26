import 'package:flutter/material.dart';

import '../services/agency_service.dart';
import 'agency_panel_screen.dart';
import 'charging_agent_screen.dart';

/// وكالتي — the entry point for a user's agencies.
///
/// A user can hold BOTH a hosting and a charging agency (#8). Previously the
/// وكيل badge opened a panel bound to whichever membership the server returned
/// first, leaving the other agency unreachable. This screen resolves that:
///
///  * no agency  → an empty state
///  * one agency → straight into that agency's own system, no menu
///  * two+       → a list, one row per agency
///
/// The single-agency case never renders a list, per the owner's requirement.
class MyAgenciesScreen extends StatefulWidget {
  const MyAgenciesScreen({super.key});

  @override
  State<MyAgenciesScreen> createState() => _MyAgenciesScreenState();
}

class _MyAgenciesScreenState extends State<MyAgenciesScreen> {
  final _service = AgencyService();

  bool _loading = true;
  List<Map<String, dynamic>> _agencies = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _service.getMyMemberships();
    if (!mounted) return;

    // Owners and branches first, then plain memberships; hosting before
    // charging so the order is stable between visits.
    final sorted = [...rows]..sort((a, b) {
        int rank(Map<String, dynamic> m) {
          final role = (m['role'] ?? '').toString();
          return role == 'OWNER' ? 0 : (role == 'BRANCH' ? 1 : 2);
        }

        final byRole = rank(a).compareTo(rank(b));
        if (byRole != 0) return byRole;
        return _typeOf(a).compareTo(_typeOf(b));
      });

    // Exactly one agency → skip the chooser entirely and replace this route so
    // Back returns to the profile rather than to an empty menu.
    if (sorted.length == 1) {
      final only = sorted.first;
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => _panelFor(only)),
      );
      return;
    }

    setState(() {
      _agencies = sorted;
      _loading = false;
    });
  }

  static String _typeOf(Map<String, dynamic> m) =>
      ((m['agency']?['type'] ?? '') as String).toUpperCase();

  /// وكالة الشحن has its own screen; hosting uses the agent panel.
  Widget _panelFor(Map<String, dynamic> membership) {
    final type = _typeOf(membership);
    if (type == 'CHARGING') return const ChargingAgentScreen();
    return AgencyPanelScreen(agencyType: type.isEmpty ? null : type);
  }

  String _roleLabel(Map<String, dynamic> m) {
    switch ((m['role'] ?? '').toString()) {
      case 'OWNER':
        return 'وكيل';
      case 'BRANCH':
        return 'فرع';
      default:
        return 'عضو';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0E3E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A0E3E),
          elevation: 0,
          title: const Text('وكالتي',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4ECDC4)))
            : _agencies.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'لست عضواً في أي وكالة',
                        style: TextStyle(color: Colors.white54, fontSize: 15),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _agencies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final m = _agencies[i];
                      final isCharging = _typeOf(m) == 'CHARGING';
                      final name = (m['agency']?['agencyName'] ?? '').toString();
                      final color =
                          isCharging ? const Color(0xFFFFB300) : const Color(0xFF4ECDC4);

                      return Material(
                        color: const Color(0xFF241A52),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => _panelFor(m)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color, width: 1.5),
                                  ),
                                  child: Icon(
                                    isCharging ? Icons.bolt : Icons.mic,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isCharging ? 'وكالة شحن' : 'وكالة مضيفين',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (name.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: color),
                                  ),
                                  child: Text(
                                    _roleLabel(m),
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_left, color: Colors.white38),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
