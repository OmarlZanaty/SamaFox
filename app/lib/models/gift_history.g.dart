// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gift_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GiftHistoryResponse _$GiftHistoryResponseFromJson(Map<String, dynamic> json) =>
    GiftHistoryResponse(
      history: (json['history'] as List<dynamic>)
          .map((e) => GiftTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      pagination:
          Pagination.fromJson(json['pagination'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GiftHistoryResponseToJson(
        GiftHistoryResponse instance) =>
    <String, dynamic>{
      'history': instance.history,
      'pagination': instance.pagination,
    };

Pagination _$PaginationFromJson(Map<String, dynamic> json) => Pagination(
      page: (json['page'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      totalPages: (json['totalPages'] as num).toInt(),
    );

Map<String, dynamic> _$PaginationToJson(Pagination instance) =>
    <String, dynamic>{
      'page': instance.page,
      'limit': instance.limit,
      'total': instance.total,
      'totalPages': instance.totalPages,
    };
