// ============================================
// PHASE 1 - CORRECTED USER PROFILE SCREEN
// ============================================
// File: lib/screens/profile/user_profile_screen.dart
// UPDATED VERSION - Uses existing User model
// Create this new screen to display user profile with gender and country

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/dio_client.dart';
import '../../services/follow_service.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final int userId;
  final bool isCurrentUser;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    this.isCurrentUser = false,
  }) : super(key: key);

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  late Future<User> _userFuture;
  late ApiService _apiService;
  String _followStatus = 'none';
  bool _updatingFollow = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(DioClient.dio);
    _userFuture = _apiService.getUserById(widget.userId);
    if (!widget.isCurrentUser) {
      _loadFollowStatus();
    }
  }

  Future<void> _loadFollowStatus() async {
    try {
      final status = await FollowService.getFollowStatus(widget.userId);
      if (mounted) setState(() => _followStatus = status);
    } catch (_) {}
  }

  Future<void> _followAction(Future<void> Function() action) async {
    if (_updatingFollow) return;
    setState(() => _updatingFollow = true);
    try {
      await action();
      await _loadFollowStatus();
      setState(() => _userFuture = _apiService.getUserById(widget.userId));
    } finally {
      if (mounted) setState(() => _updatingFollow = false);
    }
  }

  Widget _buildFollowActions() {
    if (widget.isCurrentUser) return const SizedBox.shrink();
    switch (_followStatus) {
      case 'pending_sent':
        return OutlinedButton(
          onPressed: _updatingFollow ? null : () => _followAction(() => FollowService.unfollow(widget.userId)),
          child: const Text('في الانتظار'),
        );
      case 'following':
        return OutlinedButton(
          onPressed: null,
          onLongPress: _updatingFollow ? null : () => _followAction(() => FollowService.unfollow(widget.userId)),
          child: const Text('تتابعه'),
        );
      case 'mutual':
        return const Chip(
          backgroundColor: Colors.green,
          label: Text('أصدقاء', style: TextStyle(color: Colors.white)),
        );
      case 'followed_by':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Chip(label: Text('يتابعك')),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _updatingFollow ? null : () => _followAction(() => FollowService.sendFollowRequest(widget.userId)),
              child: const Text('تابعه'),
            ),
          ],
        );
      default:
        return ElevatedButton(
          onPressed: _updatingFollow ? null : () => _followAction(() => FollowService.sendFollowRequest(widget.userId)),
          child: const Text('متابعة'),
        );
    }
  }

  /// Get gender icon based on gender value
  String _getGenderIcon(String? gender) {
    switch (gender?.toLowerCase()) {
      case 'male':
        return '👨';
      case 'female':
        return '👩';
      case 'other':
        return '🧑';
      default:
        return '❓';
    }
  }

  /// Get gender text
  String _getGenderText(String? gender) {
    switch (gender?.toLowerCase()) {
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'other':
        return 'Other';
      default:
        return 'Not specified';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<User>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Failed to load profile'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(
                          () => _userFuture = _apiService.getUserById(widget.userId),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final user = snapshot.data!;

          return SingleChildScrollView(
            child: Column(
              children: [
                // ===== HEADER SECTION =====
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade800, Colors.purple.shade600],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      CachedNetworkImage(
                        imageUrl: user.avatarUrl ?? '',
                        imageBuilder: (context, imageProvider) => CircleAvatar(
                          radius: 50,
                          backgroundImage: imageProvider,
                        ),
                        placeholder: (context, url) => CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[700],
                          child: const Icon(Icons.person, size: 50),
                        ),
                        errorWidget: (context, url, error) => CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[700],
                          child: const Icon(Icons.person, size: 50),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Name and ID
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#${user.publicDisplayId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[300],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Level and XP
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Level ${user.userLevel} • ${user.userXp} XP',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildFollowActions(),
                    ],
                  ),
                ),

                // ===== PROFILE INFO SECTION =====
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== GENDER & COUNTRY (NEW) =====
                      if (user.gender != null || user.countryCode != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[800]!),
                          ),
                          child: Row(
                            children: [
                              // Gender
                              if (user.gender != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Gender',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            _getGenderIcon(user.gender),
                                            style: const TextStyle(
                                              fontSize: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _getGenderText(user.gender),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                              // Country
                              if (user.countryCode != null)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Country',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            '🌍',
                                            style: const TextStyle(
                                              fontSize: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user.country ??
                                                      user.countryCode ??
                                                      'Unknown',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                  overflow:
                                                  TextOverflow.ellipsis,
                                                ),
                                                if (user.countryCode != null)
                                                  Text(
                                                    user.countryCode!,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[400],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // ===== BIO =====
                      if (user.bio != null && user.bio!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bio',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[800]!),
                              ),
                              child: Text(
                                user.bio!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // ===== CONTACT INFO =====
                      if (user.email != null || user.phone != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (user.email != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.email,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        user.email!,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (user.phone != null)
                              Row(
                                children: [
                                  const Icon(Icons.phone,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      user.phone!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // ===== STATS =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              label: 'Level',
                              value: user.userLevel.toString(),
                            ),
                            _StatItem(
                              label: 'XP',
                              value: user.userXp.toString(),
                            ),
                            _StatItem(
                              label: 'Coins',
                              value: user.userCoinsBalance.toString(),
                            ),
                            _StatItem(
                              label: 'VIP',
                              value: user.userVipLevel.toString(),
                            ),
                          ],
                        ),
                      ),

                      // ===== SOCIAL STATS =====
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[800]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              label: 'Followers',
                              value: user.userFollowersCount.toString(),
                            ),
                            _StatItem(
                              label: 'Following',
                              value: user.userFollowingCount.toString(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Stat item widget
class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }
}
