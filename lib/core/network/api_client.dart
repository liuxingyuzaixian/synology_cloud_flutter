import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../storage/app_preferences.dart';
import '../ui/app_dialog.dart';
import 'api_error.dart';

class ApiClient {
  ApiClient._internal() {
    _prepareDio();
  }

  factory ApiClient() => _instance;

  static final ApiClient _instance = ApiClient._internal();

  static const debugIpSwitch = 'debugIpSwitch';
  static const debugIp = 'debugIp';
  static const debugPort = 'debugPort';
  static const authTokenKey = 'authToken';

  final Dio dio = Dio();

  void setBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
  }

  Future<void> saveProxy({
    required bool enabled,
    required String host,
    required String port,
  }) async {
    await Future.wait([
      AppPreferences.putBool(debugIpSwitch, enabled),
      AppPreferences.putString(debugIp, host.trim()),
      AppPreferences.putString(debugPort, port.trim()),
    ]);
    applySavedProxy();
  }

  void applySavedProxy() {
    final enabled = AppPreferences.getBool(debugIpSwitch);
    final host = AppPreferences.getString(debugIp);
    final port = AppPreferences.getString(debugPort);
    final shouldProxy = kDebugMode && enabled && host.isNotEmpty && port.isNotEmpty;

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        if (shouldProxy) {
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
        }
        return client;
      },
    );
  }

  void _prepareDio() {
    dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 15)
      ..sendTimeout = const Duration(seconds: 15)
      ..contentType = Headers.jsonContentType
      ..responseType = ResponseType.json;

    applySavedProxy();

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = AppPreferences.getString(authTokenKey);
          if (token.isNotEmpty) {
            options.headers['token'] = token;
            options.headers['Cookie'] = 'FLYAOTHTOKEN=$token';
          }
          options.headers['accept'] = Headers.jsonContentType;
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            debugPrint('API ${response.requestOptions.method} '
                '${response.requestOptions.uri} -> ${response.statusCode}');
          }
          handler.next(response);
        },
        onError: (error, handler) {
          handler.reject(error);
        },
      ),
    );
  }

  Future<T> request<T>(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic data)? decoder,
    bool showErrorToast = true,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method),
      );

      validateResponse(response.data);
      final body = _unwrapResponseData(response.data);
      if (decoder != null) return decoder(body);
      return body as T;
    } on ApiError catch (error) {
      handleError(error, showToast: showErrorToast);
      rethrow;
    } on DioException catch (error) {
      final apiError = _fromDioException(error);
      handleError(apiError, showToast: showErrorToast);
      throw apiError;
    } catch (error) {
      final apiError = ApiError(message: '请求错误', raw: error);
      handleError(apiError, showToast: showErrorToast);
      throw apiError;
    }
  }

  void validateResponse(dynamic response) {
    if (response is! Map<String, dynamic>) return;
    if (!response.containsKey('code')) return;

    final code = response['code'];
    if (code != 8000 && code != 0 && code != 200) {
      throw ApiError(
        code: code is int ? code : int.tryParse('$code'),
        message: '${response['msg'] ?? response['message'] ?? '请求错误'}',
        raw: response,
      );
    }
  }

  dynamic _unwrapResponseData(dynamic response) {
    if (response is Map<String, dynamic> && response.containsKey('data')) {
      return response['data'];
    }
    if (response is Map<String, dynamic> && response.containsKey('result')) {
      return response['result'];
    }
    return response;
  }

  ApiError _fromDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    String message = error.message ?? '网络请求失败';

    if (data is Map<String, dynamic>) {
      message = '${data['msg'] ?? data['message'] ?? message}';
    }

    return ApiError(
      code: statusCode,
      message: message,
      raw: error,
    );
  }

  void handleError(ApiError error, {bool showToast = true}) {
    if (showToast) AppDialog.toast(error.message);

    switch (error.code) {
      case 401:
      case 403:
      case 70000:
        AppPreferences.remove(authTokenKey);
        break;
      default:
        break;
    }
  }
}
