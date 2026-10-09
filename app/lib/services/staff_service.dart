import 'package:dio/dio.dart';
import 'dio_client.dart';

typedef StaffJson = Map<String, dynamic>;
StaffJson staffJson(dynamic value) => Map<String, dynamic>.from(value as Map);
List<T> staffList<T>(dynamic value, T Function(StaffJson) parse) =>
    (value as List? ?? []).map((e) => parse(staffJson(e))).toList();
List<String> staffIds(dynamic value) => (value as List? ?? []).cast<String>();
DateTime? staffDate(dynamic value) => value == null ? null : DateTime.parse(value as String);
String staffError(Object error) => error is DioException
    ? error.error?.toString() ?? 'تعذر الاتصال، يرجى المحاولة مجدداً'
    : 'تعذر تنفيذ العملية، يرجى المحاولة مجدداً';

class StaffUser {
  StaffUser.fromJson(StaffJson j)
      : id = j['id'] as int, displayId = j['displayId'] as int?,
        name = j['name'] as String? ?? '', avatarUrl = j['avatarUrl'] as String?,
        vip = j['vipLevel'] as int? ?? 0, level = j['level'] as int? ?? 0,
        staffRole = j['staffRole'] == null ? null : StaffRole.fromJson(staffJson(j['staffRole']));
  final int id, vip, level;
  final int? displayId;
  final String name;
  final String? avatarUrl;
  final StaffRole? staffRole;
  String get label => '$name — ID ${displayId ?? id}';
}

class StaffAccess {
  StaffAccess.fromJson(StaffJson j)
      : role = j['role'] as String?, roleId = j['roleId'] as int?,
        status = j['status'] as String?, startedAt = staffDate(j['startedAt']),
        expiresAt = staffDate(j['expiresAt']),
        assignedBy = j['assignedBy'] == null ? null : StaffUser.fromJson(staffJson(j['assignedBy'])),
        permissions = staffIds(j['permissions']).toSet(),
        panels = Map<String, bool>.from(j['panels'] as Map),
        allowedItemIds = staffIds(j['allowedItemIds']);
  final String? role, status;
  final int? roleId;
  final DateTime? startedAt, expiresAt;
  final StaffUser? assignedBy;
  final Set<String> permissions;
  final Map<String, bool> panels;
  final List<String> allowedItemIds;
  bool get manager => panels['manager'] == true;
  bool get rolePanel => manager || panels['superAdmin'] == true || panels['admin'] == true;
  bool get ban => panels['ban'] == true;
  bool has(String key) => permissions.contains(key);
  bool get manages => rolePanel && (manager || role == 'SUPER_ADMIN' && has('manage_admins'));
  int get maxDays => manager ? 365 : 30;
}

class StaffRole {
  StaffRole.fromJson(StaffJson j)
      : id = j['id'] as int, userId = j['userId'] as int,
        role = j['role'] as String, status = j['status'] as String,
        startedAt = staffDate(j['startedAt']), expiresAt = staffDate(j['expiresAt']),
        allowedItemIds = staffIds(j['allowedItemIds']), rewardItemIds = staffIds(j['rewardItemIds']),
        user = j['user'] == null ? null : StaffUser.fromJson(staffJson(j['user']));
  final int id, userId;
  final String role, status;
  final DateTime? startedAt, expiresAt;
  final List<String> allowedItemIds, rewardItemIds;
  final StaffUser? user;
  bool get active => status == 'ACTIVE' && (expiresAt?.isAfter(DateTime.now()) ?? true);
  String get effectiveStatus => status == 'ACTIVE' && !active ? 'EXPIRED' : status;
}

class StaffPermission {
  StaffPermission.fromJson(StaffJson j)
      : key = j['permission'] as String, status = j['status'] as String,
        expiresAt = staffDate(j['expiresAt']), userId = j['userId'] as int,
        user = j['user'] == null ? null : StaffUser.fromJson(staffJson(j['user']));
  final String key, status;
  final DateTime? expiresAt;
  final int userId;
  final StaffUser? user;
  bool get active => status == 'ACTIVE' && (expiresAt?.isAfter(DateTime.now()) ?? true);
}

class StaffPermissionDefinition {
  StaffPermissionDefinition.fromJson(StaffJson j)
      : key = j['key'] as String, label = j['label'] as String,
        roles = (j['roles'] as List).cast<String?>();
  final String key, label;
  final List<String?> roles;
}

class StaffItem {
  StaffItem.fromJson(StaffJson j)
      : id = j['id'] as String, name = j['name'] as String,
        type = j['type'] as String, assetUrl = j['assetUrl'] as String?,
        previewUrl = j['previewUrl'] as String?;
  final String id, name, type;
  final String? assetUrl, previewUrl;
  String? get thumbnail => previewUrl?.isNotEmpty == true ? previewUrl : assetUrl;
}

class StaffGrant {
  StaffGrant.fromJson(StaffJson j)
      : id = j['id'] as int, userId = j['userId'] as int,
        grantedById = j['grantedById'] as int?, type = j['type'] as String,
        source = j['source'] as String, status = j['status'] as String,
        itemId = j['itemId'] as String?, itemType = j['itemType'] as String?,
        value = j['value'] as int?, expiresAt = staffDate(j['expiresAt']),
        startedAt = staffDate(j['startedAt']), message = j['message'] as String?,
        user = j['user'] == null ? null : StaffUser.fromJson(staffJson(j['user'])),
        grantedBy = j['grantedBy'] == null ? null : StaffUser.fromJson(staffJson(j['grantedBy'])),
        item = j['item'] == null ? null : StaffItem.fromJson(staffJson(j['item']));
  final int id, userId;
  final int? grantedById, value;
  final String type, source, status;
  final String? itemId, itemType, message;
  final DateTime? expiresAt, startedAt;
  final StaffUser? user, grantedBy;
  final StaffItem? item;
  bool get active => status == 'ACTIVE' && (expiresAt?.isAfter(DateTime.now()) ?? true);
  String get permission => type == 'VIP' ? 'grant_vip' : type == 'LEVEL' ? 'grant_level'
      : itemType == 'FRAME' ? 'grant_frame' : itemType == 'CHAT_BUBBLE' ? 'grant_bubble' : 'grant_entry';
}

class StaffHost {
  StaffHost.fromJson(StaffJson j)
      : user = StaffUser.fromJson(staffJson(j['user'])), target = j['target'] as num,
        broadcastHours = j['broadcastHours'] as num;
  final StaffUser user;
  final num target, broadcastHours;
}

class StaffAgency {
  StaffAgency.fromJson(StaffJson j)
      : id = j['id'] as int, name = j['agencyName'] as String,
        owner = StaffUser.fromJson(staffJson(j['owner'])),
        creator = j['creator'] == null ? null : StaffUser.fromJson(staffJson(j['creator'])),
        membersCount = j['membersCount'] as int, production = j['production'] as num,
        followers = staffList(j['followers'], StaffUser.fromJson),
        hosts = staffList(j['hosts'], StaffHost.fromJson);
  final int id, membersCount;
  final String name;
  final StaffUser owner;
  final StaffUser? creator;
  final num production;
  final List<StaffUser> followers;
  final List<StaffHost> hosts;
}

class StaffBan {
  StaffBan.fromJson(StaffJson j)
      : id = j['id'] as int, userId = j['userId'] as int,
        bannedById = j['bannedById'] as int, status = j['status'] as String,
        duration = j['duration'] as String, reason = j['reason'] as String,
        expiresAt = staffDate(j['expiresAt']), startedAt = staffDate(j['startedAt']),
        user = j['user'] == null ? null : StaffUser.fromJson(staffJson(j['user'])),
        bannedBy = j['bannedBy'] == null ? null : StaffUser.fromJson(staffJson(j['bannedBy']));
  final int id, userId, bannedById;
  final String status, duration, reason;
  final DateTime? expiresAt, startedAt;
  final StaffUser? user, bannedBy;
  bool get active => status == 'ACTIVE' && (expiresAt?.isAfter(DateTime.now()) ?? true);
}

class StaffAudit {
  StaffAudit.fromJson(StaffJson j)
      : action = j['action'] as String, actorId = j['adminId'] as int,
        targetUserId = j['targetUserId'] as int?, targetId = j['targetId']?.toString(),
        reason = j['reason'] as String?, createdAt = staffDate(j['createdAt']),
        targetType = j['targetType'] as String?, before = j['before'], after = j['after'],
        actor = j['actor'] == null ? null : StaffUser.fromJson(staffJson(j['actor'])),
        targetUser = j['targetUser'] == null ? null : StaffUser.fromJson(staffJson(j['targetUser']));
  final String action;
  final int actorId;
  final int? targetUserId;
  final String? targetId, reason, targetType;
  final DateTime? createdAt;
  final dynamic before, after;
  final StaffUser? actor, targetUser;
}

class StaffAuditPage {
  StaffAuditPage.fromJson(StaffJson j)
      : rows = staffList(j['rows'], StaffAudit.fromJson), page = j['page'] as int,
        total = j['total'] as int, pageSize = j['pageSize'] as int;
  final List<StaffAudit> rows;
  final int page, total, pageSize;
}

class StaffFile {
  StaffFile.fromJson(StaffJson j)
      : user = StaffUser.fromJson(staffJson(j['user'])), role = StaffRole.fromJson(staffJson(j['role'])),
        permissions = staffList(j['permissions'], StaffPermission.fromJson),
        agencies = staffList(j['agencies'], StaffAgency.fromJson),
        audit = staffList(j['audit'], StaffAudit.fromJson);
  final StaffUser user;
  final StaffRole role;
  final List<StaffPermission> permissions;
  final List<StaffAgency> agencies;
  final List<StaffAudit> audit;
}

/// Every path and envelope below comes from backend/src/staff/staff.routes.ts.
class StaffService {
  StaffService({Dio? dio}) : _dio = dio ?? DioClient.dio;
  final Dio _dio;
  Future<dynamic> _request(String path, {String method = 'GET', StaffJson? body, StaffJson? query}) async {
    final response = await _dio.request<dynamic>('/staff$path', data: body,
        queryParameters: query, options: Options(method: method));
    return staffJson(response.data)['data'];
  }
  Future<StaffAccess> me() async => StaffAccess.fromJson(staffJson(await _request('/me')));
  Future<List<StaffPermissionDefinition>> catalog() async => staffList(await _request('/permissions/catalog'), StaffPermissionDefinition.fromJson);
  Future<StaffUser> lookup(int id) async => StaffUser.fromJson(staffJson(await _request('/users/lookup', query: {'id': id})));
  Future<List<StaffRole>> members({String? status, String? role}) async => staffList(await _request('/members', query: {if (status != null) 'status': status, if (role != null) 'role': role}), StaffRole.fromJson);
  Future<StaffFile> member(int roleId) async => StaffFile.fromJson(staffJson(await _request('/members/$roleId')));
  Future<StaffRole> appoint({required int userId, required String role, required int days,
    required Map<String, bool> permissions, required List<String> allowedItemIds, int? banDays}) async =>
      StaffRole.fromJson(staffJson(await _request('/members', method: 'POST', body: {
        'userId': userId, 'role': role, 'days': days, 'permissions': permissions,
        'allowedItemIds': allowedItemIds, if (permissions['ban_users'] == true) 'expiresInDays': {'ban_users': banDays},
      })));
  Future<StaffRole> extend(int id, int days) async => StaffRole.fromJson(staffJson(await _request('/members/$id/extend', method: 'POST', body: {'days': days})));
  Future<StaffRole> renew(int id, int days) async => StaffRole.fromJson(staffJson(await _request('/members/$id/renew', method: 'POST', body: {'days': days})));
  Future<void> revoke(int id, String reason) async { await _request('/members/$id/revoke', method: 'POST', body: {'reason': reason}); }
  Future<List<StaffPermission>> setPermissions(int id, Map<String, bool> permissions, {Map<String, int?> terms = const {}}) async =>
      staffList(await _request('/members/$id/permissions', method: 'PUT', body: {'permissions': permissions, 'expiresInDays': terms}), StaffPermission.fromJson);
  Future<void> setAllowedItems(int id, List<String> ids) async { await _request('/members/$id/allowed-items', method: 'PUT', body: {'itemIds': ids}); }
  Future<void> setRewardItems(int id, List<String> ids) async { await _request('/members/$id/reward-items', method: 'PUT', body: {'itemIds': ids}); }
  Future<List<StaffPermission>> banHolders() async => staffList(await _request('/ban-holders'), StaffPermission.fromJson);
  Future<void> grantBanPermission(int userId, int? days) async { await _request('/ban-holders', method: 'POST', body: {'userId': userId, 'days': days}); }
  Future<void> revokeBanPermission(int userId) async { await _request('/ban-holders/$userId', method: 'DELETE'); }
  Future<List<StaffItem>> grantable({String? type}) async => staffList(await _request('/items/grantable', query: {if (type != null) 'type': type}), StaffItem.fromJson);
  Future<List<StaffItem>> pool({bool rewards = false}) async =>
      staffList(await _request('/items/pool', query: {if (rewards) 'scope': 'rewards'}), StaffItem.fromJson);
  Future<Map<String, List<String>>> roleRewards() async {
    final data = staffJson(await _request('/config/role-rewards'));
    return data.map((key, value) => MapEntry(key, staffIds(value)));
  }
  Future<void> setRoleRewards(String role, List<String> ids) async { await _request('/config/role-rewards', method: 'PUT', body: {role: ids}); }
  Future<StaffGrant> grantVip(int userId, int level) async => StaffGrant.fromJson(staffJson(await _request('/grants/vip', method: 'POST', body: {'userId': userId, 'level': level})));
  Future<StaffGrant> grantLevel(int userId, int level) async => StaffGrant.fromJson(staffJson(await _request('/grants/level', method: 'POST', body: {'userId': userId, 'level': level})));
  Future<StaffGrant> grantItem(int userId, String itemId) async => StaffGrant.fromJson(staffJson(await _request('/grants/item', method: 'POST', body: {'userId': userId, 'itemId': itemId})));
  Future<List<StaffGrant>> grants({String? status}) async => staffList(await _request('/grants', query: {if (status != null) 'status': status}), StaffGrant.fromJson);
  Future<void> revokeGrant(int id) async { await _request('/grants/$id/revoke', method: 'POST'); }
  Future<List<StaffAgency>> agencies() async => staffList(await _request('/agencies'), StaffAgency.fromJson);
  Future<StaffAgency> agency(int id) async => StaffAgency.fromJson(staffJson(await _request('/agencies/$id')));
  Future<int> createAgency(int ownerUserId, String name) async => staffJson(await _request('/agencies', method: 'POST', body: {'ownerUserId': ownerUserId, 'agencyName': name}))['id'] as int;
  Future<void> addFollower(int id, int staffUserId) async { await _request('/agencies/$id/followers', method: 'POST', body: {'staffUserId': staffUserId}); }
  Future<void> removeFollower(int id, int staffUserId) async { await _request('/agencies/$id/followers/$staffUserId', method: 'DELETE'); }
  Future<StaffBan> ban(int userId, String duration, String reason) async => StaffBan.fromJson(staffJson(await _request('/bans', method: 'POST', body: {'userId': userId, 'duration': duration, 'reason': reason})));
  Future<void> unban(int userId) async { await _request('/bans/$userId/unban', method: 'POST'); }
  Future<List<StaffBan>> bans({String? status}) async => staffList(await _request('/bans', query: {if (status != null) 'status': status}), StaffBan.fromJson);
  Future<StaffAuditPage> audit({int page = 1, int? actorId, String? action}) async => StaffAuditPage.fromJson(staffJson(await _request('/audit', query: {'page': page, if (actorId != null) 'actorId': actorId, if (action != null) 'action': action})));
}
