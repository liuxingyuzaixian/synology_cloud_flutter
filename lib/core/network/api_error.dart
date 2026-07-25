class ApiError implements Exception {
  const ApiError({
    required this.message,
    this.code,
    this.raw,
  });

  final String message;
  final int? code;
  final Object? raw;

  @override
  String toString() => 'ApiError(code: $code, message: $message)';
}
