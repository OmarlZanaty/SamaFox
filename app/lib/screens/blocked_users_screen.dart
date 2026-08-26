import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../services/user_account_service.dart';
import '../config/app_config.dart';

/// #2 القائمة السوداء — real blocked-users list from /users/me/blocks.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final blocks = await UserAccountService.myBlocks();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _unblock(int userId) async {
    try {
      await UserAccountService.unblock(userId);
      if (!mounted) return;
      setState(() => _blocks.removeWhere((b) => (b['user'] as Map?)?['id'] == userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الحظر')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إلغاء الحظر: $e')),
        );
      }
    }
  }

  Widget _avatar(String? avatarUrl, bool isDark) {
    String? url = avatarUrl;
    if (url != null && url.startsWith('/')) {
      url = AppConfig.socketUrl.replaceFirst(RegExp(r'/+$'), '') + url;
    }
    return CircleAvatar(
      backgroundColor: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade100,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Icon(Icons.person, color: isDark ? Colors.white70 : Colors.blue.shade700)
          : null,
    );
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
          strings.blockedUsers,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('تعذّر التحميل',
                          style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ],
                  ),
                )
              : _blocks.isEmpty
                  ? Center(
                      child: Text(
                        'لا يوجد مستخدمون محظورون',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _blocks.length,
                        itemBuilder: (context, index) {
                          final user = Map<String, dynamic>.from(
                              (_blocks[index]['user'] as Map?) ?? const {});
                          final userId = user['id'] as int?;
                          final displayId = user['displayId'];
                          return Card(
                            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: _avatar(user['avatarUrl'] as String?, isDark),
                              title: Text(
                                (user['name'] as String?) ?? 'مستخدم',
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: displayId != null
                                  ? Text('#$displayId',
                                      style: TextStyle(
                                        color: theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.6),
                                      ))
                                  : null,
                              trailing: TextButton(
                                onPressed:
                                    userId == null ? null : () => _unblock(userId),
                                child: Text(
                                  'إلغاء الحظر',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFF00A3FF),
                                  ),
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
