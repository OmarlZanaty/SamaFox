class RoomMemberView {
  final int userId;
  final String role; // owner/admin/member/audience/speaker
  final bool isMuted;
  final DateTime? joinedAt;

  final int id;
  final String name;
  final String? avatarUrl;
  final int? level;
  final int? vipLevel;

  RoomMemberView({
    required this.userId,
    required this.role,
    required this.isMuted,
    this.joinedAt,
    required this.id,
    required this.name,
    this.avatarUrl,
    this.level,
    this.vipLevel,
  });

  factory RoomMemberView.fromJson(Map<String, dynamic> json) {
    // Supports both:
    // 1) membership shape: { userId, role, isMuted, joinedAt, user: {id,name,avatarUrl,...} }
    // 2) user-only shape: { id, name, avatarUrl, level, vipLevel }
    final user = (json['user'] is Map<String, dynamic>)
        ? (json['user'] as Map<String, dynamic>)
        : <String, dynamic>{};

    // if it's user-only, prefer json['id'] / json['name']
    final int resolvedUserId = (json['userId'] ??
        json['id'] ?? // ✅ user-only list payload
        user['id'] ??
        0) as int;

    final String resolvedName =
    (user['name'] ?? json['name'] ?? '').toString(); // ✅ handle user-only

    return RoomMemberView(
      userId: resolvedUserId,
      role: (json['role'] ?? 'member').toString(),
      isMuted: (json['isMuted'] ?? false) as bool,
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : null,

      // UI identity fields:
      id: (user['id'] ?? json['id'] ?? resolvedUserId) as int, // ✅ handle user-only
      name: resolvedName,
      avatarUrl: (user['avatarUrl'] ?? json['avatarUrl']) as String?, // ✅ handle user-only
      level: (user['level'] ?? json['level']) as int?,
      vipLevel: (user['vipLevel'] ?? json['vipLevel']) as int?,
    );
  }

}

