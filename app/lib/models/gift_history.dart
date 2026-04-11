import 'package:json_annotation/json_annotation.dart';
import 'gift.dart';

part 'gift_history.g.dart';

/// Response model for gift history endpoint. Contains a list of gift transactions
/// along with pagination metadata. This mirrors the JSON returned by
/// the `/gifts/history` API endpoint on the backend.
@JsonSerializable()
class GiftHistoryResponse {
  final List<GiftTransaction> history;
  final Pagination pagination;

  GiftHistoryResponse({
    required this.history,
    required this.pagination,
  });

  factory GiftHistoryResponse.fromJson(Map<String, dynamic> json) =>
      _$GiftHistoryResponseFromJson(json);
  Map<String, dynamic> toJson() => _$GiftHistoryResponseToJson(this);
}

/// Pagination info included with paged responses.
@JsonSerializable()
class Pagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) =>
      _$PaginationFromJson(json);
  Map<String, dynamic> toJson() => _$PaginationToJson(this);
}
