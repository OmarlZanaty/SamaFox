import 'package:dio/dio.dart';

import 'dio_client.dart';

/// The server scopes every read to the authenticated owner or branch owner.
/// Never fetch a combined ledger and filter it on the device.
class AgencyBranchService {
  AgencyBranchService({Dio? dio}) : _dio = dio ?? DioClient.dio;

  final Dio _dio;
  static const transferPageSize = 100;

  static String errorMessage(Object error) {
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
    }
    if (error is AgencyBranchException) return error.message;
    return 'تعذر إتمام العملية، يرجى المحاولة مجدداً';
  }

  dynamic _data(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map || body['success'] != true) {
      throw AgencyBranchException(
        body is Map && body['message'] is String
            ? body['message'] as String
            : 'تعذر تحميل البيانات',
      );
    }
    return body['data'];
  }

  List<Map<String, dynamic>> _rows(Response<dynamic> response) {
    final data = _data(response);
    if (data is! List) {
      throw const AgencyBranchException('تعذر تحميل البيانات');
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> userById(int id) async {
    final response = await _dio.get('/users/$id');
    _data(response);
    return Map<String, dynamic>.from(response.data['user'] as Map);
  }

  Future<Map<String, dynamic>> resolveOwner(
    String value, {
    required bool internalId,
  }) async {
    final id = int.tryParse(value.trim());
    if (id == null || id <= 0) {
      throw const AgencyBranchException('أدخل رقم مستخدم صالحاً');
    }
    if (internalId) return userById(id);
    final rows = _rows(
      await _dio.get(
        '/agencies/search-user',
        queryParameters: {'q': '$id', 'agencyType': 'CHARGING'},
      ),
    );
    // Numeric name matches are also returned by this endpoint. Only an exact
    // display ID is safe; never silently assign the first search result.
    final exact = rows.where((user) => '${user['displayId']}' == '$id');
    if (exact.length != 1) {
      throw const AgencyBranchException('لم يتم العثور على مستخدم بهذا الرقم');
    }
    return exact.single;
  }

  Future<List<Map<String, dynamic>>> branches(int agencyId) async {
    final rows = _rows(await _dio.get('/agencies/$agencyId/branches'));
    // Branch records contain ownerUserId only. Resolve public identity through
    // the existing profile API, without changing the backend response contract.
    final owners = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = (row['ownerUserId'] as num).toInt();
      owners[id] ??= await userById(id);
      row['owner'] = owners[id];
    }
    return rows;
  }

  Future<void> create(int agencyId, String name, int ownerUserId) async {
    _data(
      await _dio.post(
        '/agencies/$agencyId/branches',
        data: {'name': name.trim(), 'ownerUserId': ownerUserId},
      ),
    );
  }

  Future<void> update(
    int agencyId,
    int branchId, {
    String? name,
    String? status,
  }) async {
    _data(
      await _dio.patch(
        '/agencies/$agencyId/branches/$branchId',
        data: {
          if (name != null) 'name': name.trim(),
          if (status != null) 'status': status,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> transfers(
    int agencyId, {
    int? branchId,
    int? beforeId,
  }) async {
    return _rows(
      await _dio.get(
        branchId == null
            ? '/agencies/$agencyId/transfers'
            : '/agencies/$agencyId/branches/$branchId/transfers',
        queryParameters: {if (beforeId != null) 'beforeId': beforeId},
      ),
    );
  }
}

class AgencyBranchException implements Exception {
  const AgencyBranchException(this.message);
  final String message;
}
