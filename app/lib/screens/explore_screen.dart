import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _selectedFilter = 'all';

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
        title: Text(
          strings.explore,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: theme.iconTheme.color),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.searchComingSoon)),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_list, color: theme.iconTheme.color),
            onPressed: () => _showFilterSheet(strings, theme, isDark),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Trending Section
          _buildSectionHeader(
            strings.trending,
            strings.seeAll,
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildHorizontalRoomList(theme, isDark),
          const SizedBox(height: 24),

          // Recommended Section
          _buildSectionHeader(
            strings.recommended,
            strings.seeAll,
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildVerticalRoomList(theme, isDark, strings),
          const SizedBox(height: 24),

          // Categories Section
          _buildSectionHeader(
            strings.categories,
            '',
            () {},
            theme,
            isDark,
          ),
          const SizedBox(height: 12),
          _buildCategoriesGrid(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String action,
    VoidCallback onTap,
    ThemeData theme,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (action.isNotEmpty)
          GestureDetector(
            onTap: onTap,
            child: Text(
              action,
              style: TextStyle(
                color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHorizontalRoomList(ThemeData theme, bool isDark) {
    final rooms = List.generate(5, (index) => {
      'name': 'Trending Room ${index + 1}',
      'members': (index + 1) * 10,
      'isLive': true,
    });

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF6B4CE6), const Color(0xFF2D1B69)]
                    : [const Color(0xFF00A3FF), const Color(0xFF0077CC)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? const Color(0xFF6B4CE6) : const Color(0xFF00A3FF))
                      .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        room['name'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room['members']}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (room['isLive'] as bool)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerticalRoomList(ThemeData theme, bool isDark, dynamic strings) {
    final rooms = List.generate(5, (index) => {
      'name': 'Recommended Room ${index + 1}',
      'description': 'Join us for fun conversations!',
      'members': (index + 1) * 15,
      'isLive': index % 2 == 0,
    });

    return Column(
      children: rooms.map((room) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF6B4CE6), const Color(0xFF2D1B69)]
                      : [const Color(0xFF00A3FF), const Color(0xFF0077CC)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic, color: Colors.white),
            ),
            title: Text(
              room['name'] as String,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  room['description'] as String,
                  style: TextStyle(
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.people,
                      size: 14,
                      color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${room['members']} ${strings.members}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (room['isLive'] as bool) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.iconTheme.color?.withOpacity(0.5),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoriesGrid(ThemeData theme, bool isDark) {
    final categories = [
      {'name': 'Music', 'icon': Icons.music_note},
      {'name': 'Gaming', 'icon': Icons.sports_esports},
      {'name': 'Talk', 'icon': Icons.chat_bubble},
      {'name': 'Education', 'icon': Icons.school},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  category['icon'] as IconData,
                  color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  category['name'] as String,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFilterSheet(dynamic strings, ThemeData theme, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0E3E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.sortBy,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterOption(
                    strings.all,
                    'all',
                    setModalState,
                    theme,
                    isDark,
                  ),
                  _buildFilterOption(
                    strings.popularity,
                    'popularity',
                    setModalState,
                    theme,
                    isDark,
                  ),
                  _buildFilterOption(
                    strings.newest,
                    'newest',
                    setModalState,
                    theme,
                    isDark,
                  ),
                  _buildFilterOption(
                    strings.mostMembers,
                    'members',
                    setModalState,
                    theme,
                    isDark,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(strings.apply),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterOption(
    String label,
    String value,
    StateSetter setModalState,
    ThemeData theme,
    bool isDark,
  ) {
    return RadioListTile<String>(
      title: Text(
        label,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
      ),
      value: value,
      groupValue: _selectedFilter,
      activeColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
      onChanged: (newValue) {
        setModalState(() {
          _selectedFilter = newValue!;
        });
        setState(() {
          _selectedFilter = newValue!;
        });
      },
    );
  }
}
