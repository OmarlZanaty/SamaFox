import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/locale_provider.dart';
import '../services/dio_client.dart';
import '../widgets/app_network_image.dart';
import '../l10n/tr.dart';

/// Group 12: in-app admin page — search any user by ID and ban/unban them
/// directly, with durations tiered by the caller's role (regular admin:
/// 1/2/3 days; super admin: 3d/1m/1y/permanent — enforced server-side too).
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  bool _isSuper = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyRole() async {
    try {
      final resp = await DioClient.dio.get('/admin-dashboard/me');
      final data = (resp.data is Map) ? resp.data['data'] : null;
      if (mounted && data is Map) {
        setState(() => _isSuper = data['isSuperAdmin'] == true);
      }
    } catch (_) {/* default: regular admin durations */}
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final resp = await DioClient.dio.get(
        '/admin-dashboard/users',
        queryParameters: {'search': q, 'limit': 20},
      );
      // Envelope: { success, data: [...], pagination } (ok() spreads the payload).
      final raw = (resp.data is Map) ? (resp.data['data'] as List?) : null;
      setState(() {
        _results = (raw ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      _snack(tr('فشل البحث: $e', 'Search failed: $e'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _banUser(Map<String, dynamic> user) async {
    final durations = _isSuper
        ? {
            '3d': tr('٣ أيام', '3 days'),
            '1m': tr('شهر', 'Month'),
            '1y': tr('سنة', 'Year'),
            'permanent': tr('نهائي', 'Permanent'),
          }
        : {
            '1d': tr('يوم', 'Day'),
            '2d': tr('يومان', '2 days'),
            '3d': tr('٣ أيام', '3 days'),
          };
    String duration = durations.keys.first;
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: const Color(0xFF241246),
            title: Text(tr('حظر ${user['name'] ?? ''}', 'Ban ${user['name'] ?? ''}'),
                style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: duration,
                  dropdownColor: const Color(0xFF241246),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: tr('المدة', 'Duration'),
                    labelStyle: TextStyle(color: Colors.white54),
                  ),
                  items: durations.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setLocal(() => duration = v ?? duration),
                ),
                TextField(
                  controller: reasonCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: tr('السبب', 'Reason'),
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('إلغاء', 'Cancel'),
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('حظر', 'Block')),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await DioClient.dio.put(
        '/admin/users/${user['id']}/ban',
        data: {
          'isBanned': true,
          'reason': reasonCtrl.text.trim().isEmpty
              ? 'مخالفة القوانين'
              : reasonCtrl.text.trim(),
          'duration': duration,
        },
      );
      _snack(tr('✓ تم حظر ${user['name'] ?? ''}', '✓ Banned ${user['name'] ?? ''}'));
      await _search();
    } catch (e) {
      _snack(_dioMessage(e), error: true);
    }
  }

  Future<void> _unbanUser(Map<String, dynamic> user) async {
    try {
      await DioClient.dio.put(
        '/admin/users/${user['id']}/ban',
        data: {'isBanned': false},
      );
      _snack(tr('✓ تم فك الحظر عن ${user['name'] ?? ''}', '✓ Unbanned ${user['name'] ?? ''}'));
      await _search();
    } catch (e) {
      _snack(_dioMessage(e), error: true);
    }
  }

  String _dioMessage(Object e) {
    try {
      final dynamic err = e;
      final msg = err.response?.data?['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return tr('فشل التنفيذ: $e', 'Action failed: $e');
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          strings.adminDashboard,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      keyboardType: TextInputType.text,
                      onSubmitted: (_) => _search(),
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                      decoration: InputDecoration(
                        hintText: tr('ابحث بالمعرف (ID) أو الاسم', 'Search by ID or name'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _search,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('بحث', 'Search')),
                  ),
                ],
              ),
            ),
            if (_isSuper)
              Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(tr('👑 سوبر أدمن — حظر حتى النهائي', '👑 Super admin — bans up to permanent'),
                    style: TextStyle(color: Colors.amber, fontSize: 12)),
              ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        tr('ابحث عن مستخدم بالمعرف لحظره أو فك حظره', 'Search by user ID to ban or unban'),
                        style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.6)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final u = _results[i];
                        final banned = u['isBanned'] == true;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          color: isDark ? const Color(0xFF241246) : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (u['avatarUrl'] is String &&
                                      (u['avatarUrl'] as String).isNotEmpty)
                                  ? appImage(u['avatarUrl'], 40)
                                  : null,
                              child: (u['avatarUrl'] is String &&
                                      (u['avatarUrl'] as String).isNotEmpty)
                                  ? null
                                  : const Icon(Icons.person),
                            ),
                            title: Text(
                              tr('${u['name'] ?? 'مستخدم'} — #${u['displayId'] ?? u['id']}', '${u['name'] ?? 'User'} — #${u['displayId'] ?? u['id']}'),
                              style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              banned
                                  ? tr('🚫 محظور${u['banReason'] != null ? ' — ${u['banReason']}' : ''}', '🚫 Banned${u['banReason'] != null ? ' — ${u['banReason']}' : ''}')
                                  : tr('نشط', 'Active'),
                              style: TextStyle(
                                  color: banned
                                      ? Colors.red.shade300
                                      : Colors.green.shade400),
                            ),
                            trailing: banned
                                ? OutlinedButton(
                                    onPressed: () => _unbanUser(u),
                                    child: Text(tr('فك الحظر', 'Unblock')),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade700),
                                    onPressed: () => _banUser(u),
                                    child: Text(tr('حظر', 'Block'),
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
