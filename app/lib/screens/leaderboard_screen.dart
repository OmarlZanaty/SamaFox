import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'weekly';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          strings.leaderboard,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.calendar_today, color: theme.iconTheme.color),
            color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
            onSelected: (value) {
              setState(() {
                _selectedPeriod = value;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'daily',
                child: Text(strings.daily, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              ),
              PopupMenuItem(
                value: 'weekly',
                child: Text(strings.weekly, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              ),
              PopupMenuItem(
                value: 'monthly',
                child: Text(strings.monthly, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              ),
              PopupMenuItem(
                value: 'allTime',
                child: Text(strings.allTime, style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
          labelColor: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
          unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
          tabs: [
            Tab(text: strings.topUsers),
            Tab(text: strings.topRooms),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTopUsersList(strings, theme, isDark),
          _buildTopRoomsList(strings, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildTopUsersList(dynamic strings, ThemeData theme, bool isDark) {
    final users = List.generate(
      20,
      (index) => {
        'name': 'User ${index + 1}',
        'points': (1000 - index * 50),
        'rank': index + 1,
      },
    );

    return Container(
      color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      child: Column(
        children: [
          // Top 3 podium
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildPodiumCard(users[1], 2, 100, theme, isDark),
                const SizedBox(width: 8),
                _buildPodiumCard(users[0], 1, 120, theme, isDark),
                const SizedBox(width: 8),
                _buildPodiumCard(users[2], 3, 90, theme, isDark),
              ],
            ),
          ),
          // Rest of the list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: users.length - 3,
              itemBuilder: (context, index) {
                final user = users[index + 3];
                return _buildLeaderboardItem(
                  user['rank'] as int,
                  user['name'] as String,
                  user['points'] as int,
                  strings,
                  theme,
                  isDark,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumCard(Map user, int rank, double height, ThemeData theme, bool isDark) {
    Color medalColor;
    switch (rank) {
      case 1:
        medalColor = const Color(0xFFFFD700); // Gold
        break;
      case 2:
        medalColor = const Color(0xFFC0C0C0); // Silver
        break;
      case 3:
        medalColor = const Color(0xFFCD7F32); // Bronze
        break;
      default:
        medalColor = Colors.grey;
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [medalColor, medalColor.withOpacity(0.7)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 35),
            ),
            Positioned(
              bottom: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: medalColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          user['name'] as String,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${user['points']}',
          style: TextStyle(
            color: medalColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [medalColor, medalColor.withOpacity(0.5)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardItem(
    int rank,
    String name,
    int points,
    dynamic strings,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade100,
            child: Icon(Icons.person, color: isDark ? Colors.white70 : Colors.blue.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$points',
            style: TextStyle(
              color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRoomsList(dynamic strings, ThemeData theme, bool isDark) {
    final rooms = List.generate(
      15,
      (index) => {
        'name': 'Room ${index + 1}',
        'members': (500 - index * 30),
        'rank': index + 1,
      },
    );

    return Container(
      color: isDark ? const Color(0xFF0D0620) : Colors.grey.shade50,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0E3E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D1B69) : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${room['rank']}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFFD700) : const Color(0xFF00A3FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room['name'] as String,
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 14,
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room['members']} ${strings.members}',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.iconTheme.color?.withOpacity(0.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
