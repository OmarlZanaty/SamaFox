class Result<T> {
  final T? data;
  final String? error;
  final bool isLoading;

  Result._({this.data, this.error, this.isLoading = false});

  factory Result.success(T data) => Result._(data: data);
  factory Result.error(String error) => Result._(error: error);
  factory Result.loading() => Result._(isLoading: true);

  bool get isSuccess => data != null && error == null;
  bool get isError => error != null;
}
