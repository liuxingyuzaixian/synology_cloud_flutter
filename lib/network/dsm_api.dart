import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../models/server_model.dart';
import '../utils/app_preferences.dart';
import '../utils/fly_router.dart';
import '../components/app_dialog.dart';

/// DSM Web API 封装层
/// 将群晖 DSM 的 SYNO.* API 封装为类型安全的 Dart 方法
class DsmApi {
  DsmApi._internal();
  factory DsmApi() => _instance;
  static final DsmApi _instance = DsmApi._internal();

  // 当前连接的服务器信息
  ServerModel? _server;
  ServerModel? get server => _server;

  // DSM API 注册表 (SYNO.API.Info 查询结果)
  Map<String, Map<String, dynamic>> _apiRegistry = {};

  // Session
  String _sid = '';
  String _cookie = '';
  String _synoToken = '';
  int _dsmVersion = 7;

  String get sid => _sid;
  String get cookie => _cookie;
  String get synoToken => _synoToken;
  Map<String, String> get authHeaders => {'Cookie': _cookie};
  int get dsmVersion => _dsmVersion;
  String get baseUrl => _server?.fullUrl ?? '';

  // ==================== Dio 实例管理 ====================

  Dio _createDio({String? host, bool? checkSsl}) {
    final dio = Dio();
    final targetHost = host ?? baseUrl;
    final sslCheck = checkSsl ?? _server?.checkSsl ?? true;

    dio.options
      ..connectTimeout = const Duration(seconds: 20)
      ..receiveTimeout = const Duration(seconds: 20)
      ..sendTimeout = const Duration(seconds: 60)
      ..headers = {
        'Cookie': _cookie,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'origin': targetHost,
        'referer': targetHost,
      };

    // SSL 证书校验
    if (!sslCheck) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        },
      );
    }

    // Debug / manual proxy (apply regardless of build mode)
    final proxyEnabled = AppPreferences.getBool('debugIpSwitch');
    final proxyHost = AppPreferences.getString('debugIp');
    final proxyPort = AppPreferences.getString('debugPort');
    if (proxyEnabled && proxyHost.isNotEmpty && proxyPort.isNotEmpty) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $proxyHost:$proxyPort';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        },
      );
    }

    return dio;
  }

  // ==================== 核心请求方法 ====================

  /// GET 请求
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? data,
    String? host,
    bool? checkSsl,
    String? cookie,
    CancelToken? cancelToken,
  }) async {
    final dio = _createDio(host: host, checkSsl: checkSsl);
    if (cookie != null) {
      dio.options.headers['Cookie'] = cookie;
    }
    final targetHost = host ?? baseUrl;
    dio.options.baseUrl = path.startsWith('http') ? '' : '$targetHost/webapi/';

    try {
      final response = await dio.get(
        path,
        queryParameters: data,
        cancelToken: cancelToken,
      );
      // 登录时处理 cookie
      if (path == 'auth.cgi') {
        debugPrint('【调试】auth.cgi 原始响应数据: ${response.data}');
        _handleLoginCookies(response);
      }
      return _parseResponse(response.data);
    } on DioException catch (e) {
      return _handleDioError(e, path);
    }
  }

  /// POST 请求
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? data,
    String? host,
    bool? checkSsl,
    String? cookie,
    CancelToken? cancelToken,
  }) async {
    final dio = _createDio(host: host, checkSsl: checkSsl);
    if (cookie != null) {
      dio.options.headers['Cookie'] = cookie;
    }
    final targetHost = host ?? baseUrl;
    dio.options.baseUrl = '$targetHost/webapi/';
    dio.options.contentType = 'application/x-www-form-urlencoded';

    try {
      final response = await dio.post(
        path,
        data: data,
        cancelToken: cancelToken,
      );
      return _parseResponse(response.data);
    } on DioException catch (e) {
      return _handleDioError(e, path);
    }
  }

  /// 文件上传
  Future<dynamic> upload(
    String path, {
    Map<String, dynamic>? params,
    required Map<String, dynamic> data,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) async {
    final dio = _createDio();
    dio.options.baseUrl = '$baseUrl/webapi/';
    dio.options.headers['Accept-Encoding'] = 'gzip, deflate';
    dio.options.headers['Accept'] = '*/*';

    final formData = FormData.fromMap(data);
    try {
      final response = await dio.post(
        path,
        queryParameters: params,
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );
      return _parseResponse(response.data);
    } on DioException catch (e) {
      return _handleDioError(e, path);
    }
  }

  dynamic _parseResponse(dynamic data) {
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map) _checkAuthError(parsed);
        return parsed;
      } catch (_) {
        return data;
      }
    }
    if (data is Map) {
      _checkAuthError(data);
    }
    return data;
  }

  Map _handleDioError(DioException error, String path) {
    String code = '';
    if (error.message != null &&
        error.message!.contains('CERTIFICATE_VERIFY_FAILED')) {
      code = 'SSL/HTTPS证书有误';
    } else {
      code = error.message ?? '网络错误';
    }
    debugPrint('请求出错: $baseUrl/$path - $code');
    return {
      'success': false,
      'error': {'code': code},
      'data': null,
    };
  }

  void _checkAuthError(Map parsed) {
    try {
      if (parsed.containsKey('error') && parsed['error'] is Map) {
        final err = parsed['error'] as Map;
        if (err['code'] == 119) {
          _handleLogout();
          return;
        }
      }

      if (parsed.containsKey('data') && parsed['data'] is Map) {
        final d = parsed['data'] as Map;
        if (d['has_fail'] == true && d['result'] is List) {
          for (final item in d['result'] as List) {
            if (item is Map && item['error'] is Map && item['error']['code'] == 119) {
              _handleLogout();
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _handleLogout() {
    _sid = '';
    _cookie = '';
    _synoToken = '';
    _server = null;

    try {
      AppPreferences.remove('sid');
      AppPreferences.remove('smid');
      AppPreferences.remove('syno_token');
    } catch (_) {}

    try {
      AppDialog.toast('会话已失效，请重新登录');
      final navigator = FlyRouter().navigatorKey.currentState;
      navigator?.pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (_) {}
  }

  void _handleLoginCookies(Response response) {
    final setCookies = response.headers.map['set-cookie'];
    debugPrint('【调试】Set-Cookie 原始值: $setCookies');
    if (setCookies == null || setCookies.isEmpty) return;

    // 从原始 cookie 中提取 did
    String did = '';
    if (_cookie.isNotEmpty) {
      for (final c in _cookie.split('; ')) {
        final cookie = Cookie.fromSetCookieValue(c);
        if (cookie.name == 'did') did = cookie.value;
      }
    }

    final cookies = <String>[];
    bool haveDid = false;
    for (final sc in setCookies) {
      final cookie = Cookie.fromSetCookieValue(sc);
      cookies.add('${cookie.name}=${cookie.value}');
      if (cookie.name == 'did') haveDid = true;
      // 从 Set-Cookie 中提取 SynoToken（DSM 可能放在 cookie 里而非 JSON body）
      if (cookie.name.toLowerCase() == 'syno_token' && cookie.value.isNotEmpty) {
        setSynoToken(cookie.value);
      }
    }
    if (!haveDid && did.isNotEmpty) {
      cookies.add('did=$did');
    }
    _cookie = cookies.join('; ');
    AppPreferences.putString('smid', _cookie);
  }

  // ==================== 认证 ====================

  /// 设置当前服务器
  void setServer(ServerModel server) {
    _server = server;
    _sid = server.sid ?? '';
    _cookie = server.cookie ?? '';
    _dsmVersion = server.dsmVersion;
  }

  /// 查询所有可用 API
  Future<Map> queryApis() async {
    final res = await post('query.cgi', data: {
      'query': 'all',
      'api': 'SYNO.API.Info',
      'method': 'query',
      'version': 1,
    });
    if (res is String) return jsonDecode(res);
    return res;
  }

  /// 登录
  Future<Map> login({
    String? host,
    required String account,
    required String password,
    String otpCode = '',
    String? otpToken,
    CancelToken? cancelToken,
    bool rememberDevice = false,
    String? cookie,
  }) async {
    final data = <String, dynamic>{
      'account': account,
      'passwd': password,
      'otp_code': otpCode,
      'version': 7,
      'api': 'SYNO.API.Auth',
      'method': 'login',
      'session': 'FileStation',
      'enable_device_token': rememberDevice ? 'yes' : 'no',
      'enable_sync_token': 'yes',
      'isIframeLogin': 'yes',
    };
    if (otpToken != null && otpToken.isNotEmpty) {
      data['otp_token'] = otpToken;
    }
    return await get(
      'auth.cgi',
      host: host,
      data: data,
      cancelToken: cancelToken,
      cookie: cookie,
    );
  }

  /// 刷新 / 获取 SynoToken（登录后随时可调用，无需重新登录）
  Future<String> refreshSynoToken() async {
    // 方式1：优先从登录响应中获取（version 7 登录时已返回）
    if (_synoToken.isNotEmpty) return _synoToken;

    // 方式2：调用 token API（注：需完整 web session 作用域，app session 可能不返回）
    final res = await post('entry.cgi/SYNO.API.Auth', data: {
      'api': 'SYNO.API.Auth',
      'method': 'token',
      'version': 6,
      '_sid': _sid,
      'updateSynoToken': true,
    });
    final token = res is Map ? (res['data']?['synotoken'] ?? '') : '';
    if (token is String && token.isNotEmpty) {
      setSynoToken(token);
    }
    return token is String ? token : '';
  }

  /// 登出
  Future<Map> logout() async {
    return await get('auth.cgi', data: {
      'api': 'SYNO.API.Auth',
      'method': 'logout',
      'version': 6,
      '_sid': _sid,
    });
  }

  /// 设置 session
  void setSession({required String sid, required String cookie}) {
    _sid = sid;
    _cookie = cookie;
    AppPreferences.putString('smid', cookie);
  }

  /// 设置 SynoToken（用于 WebView 自动登录）
  void setSynoToken(String token) {
    debugPrint('【调试】setSynoToken 被调用，token 长度=${token.length}, 是否为空=${token.isEmpty}');
    _synoToken = token;
    if (token.isNotEmpty) {
      AppPreferences.putString('syno_token', token);
      debugPrint('【调试】syno_token 已保存到 AppPreferences');
    }
  }

  // ==================== QuickConnect ====================

  /// QuickConnect 全球服务器
  Future<Map> quickConnect(String qcId,
      {String baseUrl = 'global.quickconnect.cn'}) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 10);
    try {
      final response = await dio.post(
        'https://$baseUrl/Serv.php',
        data: {
          'version': '1',
          'id': 'dsm_portal_https',
          'serverID': '"$qcId"',
          'command': '"request_tunnel"',
          'stop_when_error': '"false"',
          'isIframeLogin': '"yes"',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return response.data;
    } catch (e) {
      return {'errno': -1, 'errinfo': e.toString()};
    }
  }

  /// QuickConnect 中国服务器
  Future<Map> quickConnectCn(String qcId,
      {required String baseUrl}) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 10);
    try {
      final response = await dio.post(
        'https://$baseUrl/Serv.php',
        data: {
          'version': '1',
          'id': 'dsm_portal_https',
          'serverID': '"$qcId"',
          'command': '"request_tunnel"',
          'stop_when_error': '"false"',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return response.data;
    } catch (e) {
      return {'errno': -1, 'errinfo': e.toString()};
    }
  }

  /// Ping-Pong 检测服务器可用性
  Future<String?> pingpong(String address) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 5);
    try {
      final response = await dio.get(
        '$address/webapi/entry.cgi',
        queryParameters: {
          'api': 'SYNO.API.Info',
          'version': 1,
          'method': 'query',
          'query': 'all',
        },
      );
      if (response.data != null) {
        return address;
      }
    } catch (_) {}
    return null;
  }

  // ==================== File Station ====================

  /// 获取共享文件夹列表
  Future<Map> shareList({
    List<String> additional = const ['perm', 'time', 'size'],
    CancelToken? cancelToken,
  }) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.List"',
      'method': '"list_share"',
      'version': 2,
      '_sid': _sid,
      'offset': 0,
      'limit': 1000,
      'sort_by': '"name"',
      'sort_direction': '"asc"',
      'additional': jsonEncode(additional),
    }, cancelToken: cancelToken);
  }

  /// 获取文件列表
  Future<Map> fileList(
    String path, {
    String sortBy = 'name',
    String sortDirection = 'asc',
  }) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.List"',
      'method': '"list"',
      'version': 2,
      '_sid': _sid,
      'offset': 0,
      'folder_path': path,
      'filetype': '"all"',
      'limit': 5000,
      'sort_by': '"$sortBy"',
      'sort_direction': '"$sortDirection"',
      'additional': '["perm", "time", "size","mount_point_type","real_path"]',
    });
  }

  /// 创建文件夹
  Future<Map> createFolder(String path, String name) async {
    return await get('entry.cgi', data: {
      'api': '"SYNO.FileStation.CreateFolder"',
      'method': '"create"',
      'version': 2,
      'force_parent': 'false',
      'folder_path': '"$path"',
      'name': '"$name"',
      '_sid': _sid,
    });
  }

  /// 重命名
  Future<Map> rename(String path, String name) async {
    return await get('entry.cgi', data: {
      'api': '"SYNO.FileStation.Rename"',
      'method': '"rename"',
      'version': 2,
      'path': '"$path"',
      'name': '"$name"',
      '_sid': _sid,
    });
  }

  /// 删除文件
  Future<Map> deleteTask(List<String> paths) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Delete"',
      'method': '"start"',
      'accurate_progress': 'true',
      'version': 2,
      '_sid': _sid,
      'path': jsonEncode(paths),
    });
  }

  /// 删除结果查询
  Future<Map> deleteResult(String taskId) async {
    return await post('entry.cgi', data: {
      'taskid': taskId,
      'api': '"SYNO.FileStation.Delete"',
      'method': '"status"',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 搜索文件
  Future<Map> searchTask(
    List<String> paths,
    String pattern, {
    bool recursive = true,
  }) async {
    return await post('entry.cgi', data: {
      'folder_path': jsonEncode(paths),
      'api': 'SYNO.FileStation.Search',
      'method': '"start"',
      'pattern': '"$pattern"',
      'recursive': recursive,
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 搜索结果
  Future<Map> searchResult(String taskId) async {
    return await post('entry.cgi', data: {
      'additional':
          jsonEncode(['real_path', 'size', 'owner', 'time', 'perm', 'type']),
      'taskid': taskId,
      'offset': 0,
      'limit': 1000,
      'filetype': 'all',
      'api': '"SYNO.FileStation.Search"',
      'method': '"list"',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 复制/移动文件
  Future<Map> copyMoveTask(
      List paths, String destFolderPath, bool removeSrc) async {
    return await post('entry.cgi', data: {
      'overwrite': 'true',
      'dest_folder_path': destFolderPath,
      'api': '"SYNO.FileStation.CopyMove"',
      'remove_src': removeSrc,
      'accurate_progress': 'true',
      'method': '"start"',
      'version': 3,
      '_sid': _sid,
      'path': jsonEncode(paths),
    });
  }

  /// 复制/移动结果
  Future<Map> copyMoveResult(String taskId) async {
    return await post('entry.cgi', data: {
      'taskid': taskId,
      'api': '"SYNO.FileStation.CopyMove"',
      'method': '"status"',
      'version': 3,
      '_sid': _sid,
    });
  }

  /// 压缩文件
  Future<Map> compressTask(
    List<String> paths,
    String destPath, {
    String level = 'normal',
    String format = 'zip',
    String? password,
  }) async {
    final data = {
      'api': '"SYNO.FileStation.Compress"',
      'method': '"start"',
      'version': 3,
      '_sid': _sid,
      'path': jsonEncode(paths),
      'dest_file_path': destPath,
      'level': level,
      'mode': 'replace',
      'format': format,
      'password': password,
    };
    return await post('entry.cgi', data: data);
  }

  /// 解压
  Future<Map> extractTask(String filePath, String folderPath,
      {String? password}) async {
    final data = {
      'api': '"SYNO.FileStation.Extract"',
      'overwrite': 'false',
      'method': '"start"',
      'version': 2,
      '_sid': _sid,
      'file_path': filePath,
      'dest_folder_path': folderPath,
      'keep_dir': 'true',
      'create_subfolder': 'false',
    };
    if (password != null) data['password'] = '"$password"';
    return await post('entry.cgi', data: data);
  }

  /// 文件上传
  Future<Map> uploadFile(
    String uploadPath,
    String filePath,
    CancelToken cancelToken,
    void Function(int, int) onSendProgress,
  ) async {
    final file = File(filePath);
    final multipartFile = MultipartFile.fromFileSync(
      filePath,
      filename: filePath.split('/').last,
    );
    final params = {
      'api': 'SYNO.FileStation.Upload',
      'method': 'upload',
      'version': 3,
    };
    final data = {
      'path': uploadPath,
      'create_parents': true,
      'size': file.lengthSync(),
      'mtime': file.lastModifiedSync().millisecondsSinceEpoch,
      'overwrite': false,
      'file': multipartFile,
    };
    return await upload(
      'entry.cgi',
      params: params,
      data: data,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  /// 创建分享链接
  Future<Map> createShare(List<String> paths) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Sharing"',
      'method': '"create"',
      'version': 3,
      '_sid': _sid,
      'path': jsonEncode(paths),
    });
  }

  /// 分享列表
  Future<Map> listShare() async {
    return await post('entry.cgi', data: {
      'offset': 0,
      'limit': 100,
      'filter_type':
          'SYNO.SDS.App.FileStation3.Instance,SYNO.SDS.App.SharingUpload.Application',
      'api': '"SYNO.FileStation.Sharing"',
      'method': '"list"',
      'version': 3,
      '_sid': _sid,
    });
  }

  /// 删除分享链接 (支持批量)
  Future<Map> deleteShare(List<String> ids) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Sharing"',
      'method': '"delete"',
      'version': 3,
      '_sid': _sid,
      'id': jsonEncode(ids),
    });
  }

  /// 收藏列表
  Future<Map> favoriteList() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Favorite"',
      'method': '"list"',
      'version': 2,
      '_sid': _sid,
      'offset': 0,
      'limit': 1000,
      'additional': '["perm", "time", "size","real_path"]',
    });
  }

  /// 添加收藏
  Future<Map> favoriteAdd(String name, String path) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Favorite"',
      'method': '"add"',
      'version': 2,
      '_sid': _sid,
      'name': name,
      'path': path,
      'index': -1,
    });
  }

  /// 删除收藏
  Future<Map> favoriteDelete(String path) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Favorite"',
      'method': '"delete"',
      'version': 2,
      '_sid': _sid,
      'path': path,
    });
  }

  /// 重命名收藏
  Future<Map> favoriteRename(String path, String name) async {
    return await get('entry.cgi', data: {
      'api': '"SYNO.FileStation.Favorite"',
      'method': '"edit"',
      'version': 2,
      '_sid': _sid,
      'path': path,
      'name': name,
    });
  }

  /// 目录大小
  Future<Map> dirSizeTask(String path) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.DirSize"',
      'method': '"start"',
      'version': 1,
      '_sid': _sid,
      'path': path,
    });
  }

  /// 目录大小结果
  Future<Map> dirSizeResult(String taskId) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.DirSize"',
      'method': '"status"',
      'version': 1,
      '_sid': _sid,
      'taskid': taskId,
    });
  }

  /// 后台任务列表
  Future<Map> backgroundTask() async {
    return await post('entry.cgi', data: {
      'is_list_sharemove': true,
      'is_vfs': true,
      'bkg_info': true,
      'api': 'SYNO.FileStation.BackgroundTask',
      'method': 'list',
      'version': 3,
      '_sid': _sid,
    });
  }

  // ==================== 系统信息 ====================

  /// 系统信息
  Future<Map> systemInfo() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.System"',
      'method': '"info"',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 系统资源使用
  Future<Map> utilization({
    String? sid,
    bool? checkSsl,
    String? cookie,
    String? host,
  }) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.System.Utilization',
      'method': 'get',
      'version': 1,
      'type': 'current',
      'resource': ['cpu', 'memory', 'network', 'lun', 'disk', 'space'],
      '_sid': sid ?? _sid,
    }, checkSsl: checkSsl, cookie: cookie, host: host);
  }

  /// 仪表盘初始化数据 (批量请求)
  Future<Map> dashboardData() async {
    final apis = [
      {
        'api': 'SYNO.Core.System.Utilization',
        'method': 'get',
        'version': 1,
        'type': 'current',
        'resource': ['cpu', 'memory', 'network', 'disk']
      },
      {
        'api': 'SYNO.Storage.CGI.Storage',
        'method': 'load_info',
        'version': 1,
      },
      {
        'api': 'SYNO.Core.System',
        'method': 'info',
        'version': 1,
      },
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"parallel"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 存储信息
  Future<Map> storage() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Storage.CGI.Storage',
      'method': 'load_info',
      'version': 1,
    });
  }

  /// 网络信息
  Future<Map> networkInfo() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.System"',
      'method': '"info"',
      'version': 1,
      'type': 'network',
      '_sid': _sid,
    });
  }

  /// 重启/关机
  Future<Map> power(String method, bool force) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.System"',
      'force': force,
      'local': true,
      'version': 1,
      'method': method,
      '_sid': _sid,
    });
  }

  /// 进程列表
  Future<Map> process() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.System.Process',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 进程组
  Future<Map> processGroup() async {
    final data = {
      'api': 'SYNO.Core.System.ProcessGroup',
      'method': _dsmVersion == 7 ? 'list' : 'service_info',
      'version': 1,
      '_sid': _sid,
    };
    if (_dsmVersion == 7) data['node'] = 'xnode-2572';
    return await post('entry.cgi', data: data);
  }

  // ==================== 通知 ====================

  /// 获取通知字符串模板（用于格式化通知内容）
  Future<Map> notifyStrings() async {
    return await post('entry.cgi', data: {
      'pkgName': '""',
      'lang': '"chs"',
      'api': 'SYNO.Core.DSMNotify.Strings',
      'method': 'get',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 获取通知
  Future<Map> notify() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.DSMNotify"',
      'method': '"notify"',
      'version': 1,
      '_sid': _sid,
      'action': '"load"',
      'lastRead': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'lastSeen': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// 清除通知
  Future<Map> clearNotify() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.DSMNotify"',
      'method': '"notify"',
      'version': 1,
      '_sid': _sid,
      'action': '"apply"',
      'clean': '"all"',
    });
  }

  /// 当前连接列表
  Future<Map> currentConnection() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.CurrentConnection"',
      'method': '"list"',
      'sort_direction': 'DESC',
      'sort_by': 'time',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 踩断连接
  Future<Map> kickConnection(Map<String, dynamic> connection) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.CurrentConnection"',
      'method': '"kick_connection"',
      'version': 1,
      '_sid': _sid,
      'http_conn': jsonEncode(connection),
      'service_conn': '[]',
    });
  }

  // ==================== Synology Photos ====================

  /// 时间线 (DSM 7)
  Future<Map> fotoTimeline({
    int offset = 0,
    int limit = 100,
    String? album,
  }) async {
    final data = {
      'api': 'SYNO.Foto.Browse.Timeline',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort': '"date"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    };
    if (album != null) data['album'] = album;
    return await post('entry.cgi', data: data);
  }

  /// 相册列表 (DSM 7)
  Future<Map> fotoAlbums({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Album',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort_by': '"create_time"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    });
  }

  /// 共享相册列表 (DSM 7)
  Future<Map> fotoSharedAlbums({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Album',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'shared': true,
      'sort_by': '"create_time"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    });
  }

  /// 文件夹列表 (DSM 7)
  Future<Map> fotoFolders({String folder = '/'}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Folder',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'folder': '"$folder"',
    });
  }

  /// 最近添加 (DSM 7)
  Future<Map> fotoRecentlyAdded({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.RecentlyAdded',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// 地理位置照片 (DSM 7)
  Future<Map> fotoGeocoding({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Geocoding',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// AI 标签 (DSM 7)
  Future<Map> fotoGeneralTag({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.GeneralTag',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// 分类 (DSM 7)
  Future<Map> fotoCategory() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Category',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 删除照片 (支持批量)
  Future<Map> fotoDeleteItem(List<int> ids) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Browse.Item',
      'method': 'delete',
      'version': 6,
      '_sid': _sid,
      'id': jsonEncode(ids),
    });
  }

  // ==================== 共享空间 (Team Space) API ====================

  /// 共享空间 — 浏览照片列表
  Future<Map> fotoTeamBrowseItem({
    int offset = 0,
    int limit = 100,
    int? albumId,
    int? folderId,
    int? generalTagId,
    int? geocodingId,
    String? type,
  }) async {
    final data = <String, dynamic>{
      'api': 'SYNO.FotoTeam.Browse.Item',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort_by': '"takentime"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    };
    if (albumId != null) data['album_id'] = albumId;
    if (folderId != null) data['folder_id'] = folderId;
    if (generalTagId != null) data['general_tag_id'] = generalTagId;
    if (geocodingId != null) data['geocoding_id'] = geocodingId;
    if (type != null) data['type'] = '"$type"';
    return await post('entry.cgi', data: data);
  }

  /// 共享空间 — 相册列表
  Future<Map> fotoTeamAlbums({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.Album',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort_by': '"create_time"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    });
  }

  /// 共享空间 — 共享相册列表
  Future<Map> fotoTeamSharedAlbums({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.Album',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'shared': true,
      'sort_by': '"create_time"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    });
  }

  /// 共享空间 — 最近添加
  Future<Map> fotoTeamRecentlyAdded({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.RecentlyAdded',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// 共享空间 — 文件夹列表
  Future<Map> fotoTeamFolders({String folder = '/'}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.Folder',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'folder': '"$folder"',
    });
  }

  /// 共享空间 — 地理位置照片
  Future<Map> fotoTeamGeocoding({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.Geocoding',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// 共享空间 — AI 标签
  Future<Map> fotoTeamGeneralTag({int offset = 0, int limit = 100}) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FotoTeam.Browse.GeneralTag',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'additional': '["thumbnail"]',
    });
  }

  /// 缩略图 URL
  /// size: 0=sm, 1=m, 2=lg, 3=xl, 4=xxl
  String fotoThumbnailUrl(int itemId, {int size = 3, String? cacheKey}) {
    const sizeMap = ['sm', 'm', 'lg', 'xl', 'xxl'];
    final sizeStr = sizeMap[size.clamp(0, 4)];
    final ck = cacheKey ?? itemId.toString();
    return '$baseUrl/webapi/entry.cgi?id=$itemId&cache_key="$ck"&type="unit"&size="$sizeStr"&api="SYNO.Foto.Thumbnail"&method="get"&version=1&_sid=$_sid';
  }

  /// 团队空间缩略图 URL
  String fotoTeamThumbnailUrl(int itemId, {int size = 3, String? cacheKey}) {
    const sizeMap = ['sm', 'm', 'lg', 'xl', 'xxl'];
    final sizeStr = sizeMap[size.clamp(0, 4)];
    final ck = cacheKey ?? itemId.toString();
    return '$baseUrl/webapi/entry.cgi?id=$itemId&cache_key="$ck"&type="unit"&size="$sizeStr"&api="SYNO.FotoTeam.Thumbnail"&method="get"&version=1&_sid=$_sid';
  }

  /// 照片下载 URL
  String fotoDownloadUrl(int itemId) {
    return '$baseUrl/webapi/entry.cgi?api=SYNO.Foto.Download&method=download&version=1&_sid=$_sid&item_id=%5B$itemId%5D';
  }

  /// 视频转码流的默认清晰度。
  ///
  /// 群晖 Photos 会为每个视频预生成低码率转码版本（H.264），用它播放
  /// 比拉原始文件（常为 4K/HEVC 高码率）码率更低、更易解码，能显著改善
  /// 弱网卡顿。可选：low / medium / high / original / mobile。
  /// 若担心 1080p 仍偏大可改为 'medium'（720p）或 'low'（360p）。
  static const String fotoVideoQuality = 'high';

  /// 视频转码流 URL (SYNO.Foto.Streaming)。
  ///
  /// [id] 传视频的 item id（与 [fotoDownloadUrl] 相同的标识）。若该清晰度
  /// 尚未在 NAS 上转码完成，服务器会返回 404 / JSON 错误，调用方必须回退到
  /// [fotoDownloadUrl] 播放原始文件。
  String fotoStreamingUrl(int id, {String quality = fotoVideoQuality}) {
    return '$baseUrl/webapi/entry.cgi?api=SYNO.Foto.Streaming&method=streaming&version=1&_sid=$_sid&id=$id&quality=$quality';
  }

  /// 浏览照片列表 (DSM 7) — 用于时间线/相册详情/标签详情等
  Future<Map> fotoBrowseItem({
    int offset = 0,
    int limit = 100,
    int? albumId,
    int? folderId,
    int? generalTagId,
    int? geocodingId,
    String? type,
  }) async {
    final data = <String, dynamic>{
      'api': 'SYNO.Foto.Browse.Item',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort_by': '"takentime"',
      'sort_direction': '"desc"',
      'additional': '["thumbnail"]',
    };
    if (albumId != null) data['album_id'] = albumId;
    if (folderId != null) data['folder_id'] = folderId;
    if (generalTagId != null) data['general_tag_id'] = generalTagId;
    if (geocodingId != null) data['geocoding_id'] = geocodingId;
    if (type != null) data['type'] = '"$type"';
    return await post('entry.cgi', data: data);
  }

  /// Moments 时间线 (DSM 6)
  Future<Map> photoTimeline({
    int offset = 0,
    int limit = 100,
  }) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Photo.Browse.Timeline',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'offset': offset,
      'limit': limit,
      'sort': '"date"',
    });
  }

  // ==================== Download Station ====================

  /// Download Station 信息 (批量)
  Future<Map> downloadStationInfo() async {
    final apis = [
      {
        'api': 'SYNO.DownloadStation2.Task',
        'method': 'list',
        'version': 2,
        'limit': 500,
        'offset': 0,
        'sort_by': 'task_id',
        'order': 'ASC',
        'additional': ['detail', 'transfer'],
        'type': ['emule'],
        'type_inverse': true,
      },
      {
        'api': 'SYNO.DownloadStation2.Task.Statistic',
        'method': 'get',
        'version': 1,
        'type': ['emule'],
        'type_inverse': true,
      },
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"parallel"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 下载任务操作
  Future<Map> downloadTaskAction(List id, String action) async {
    return await post('entry.cgi', data: {
      'id': jsonEncode(id),
      'api': 'SYNO.DownloadStation2.Task',
      'method': action,
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 创建下载任务
  Future<Map> downloadTaskCreate(
    String destination,
    String type, {
    String? url,
    String? filePath,
  }) async {
    final data = {
      'api': 'SYNO.DownloadStation2.Task',
      'method': 'create',
      'version': 2,
    };
    if (type == 'file' && filePath != null) {
      final torrent = MultipartFile.fromFileSync(
        filePath,
        filename: filePath.split('/').last,
      );
      data['file'] = jsonEncode(['-1891550746']);
      data['type'] = '"$type"';
      data['create_list'] = true;
      data['destination'] = '"$destination"';
      data['-1891550746'] = torrent;
      return await upload('entry.cgi', data: data);
    } else {
      final urls = (url ?? '').split('\n').where((u) => u.trim().isNotEmpty).toList();
      data['type'] = '"$type"';
      data['create_list'] = true;
      data['url'] = jsonEncode(urls);
      data['destination'] = '"$destination"';
      data['_sid'] = _sid;
      return await post('entry.cgi', data: data);
    }
  }

  /// 下载位置
  Future<Map> downloadLocation() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Settings.Location',
      'method': 'get',
      'version': 1,
      '_sid': _sid,
    });
  }

  // ==================== Docker ====================

  /// Docker 容器信息 (批量)
  Future<Map> dockerContainerInfo() async {
    final apis = [
      {
        'api': 'SYNO.Docker.Container',
        'method': 'list',
        'version': 1,
        'limit': -1,
        'offset': 0,
        'type': 'all'
      },
      {
        'api': 'SYNO.Docker.Container.Resource',
        'method': 'get',
        'version': 1,
      },
      {
        'api': 'SYNO.Core.System.Utilization',
        'method': 'get',
        'version': 1,
      },
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"parallel"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// Docker 镜像信息
  Future<Map> dockerImageInfo() async {
    final apis = [
      {
        'api': 'SYNO.Docker.Image',
        'method': 'list',
        'version': 1,
        'limit': -1,
        'offset': 0,
        'show_dsm': false
      },
      {
        'api': 'SYNO.Docker.Registry',
        'method': 'get',
        'version': 1,
        'limit': -1,
        'offset': 0
      }
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"parallel"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// Docker 容器操作
  Future<Map> dockerPower(String name, String action,
      {bool? preserveProfile}) async {
    final data = {
      'api': 'SYNO.Docker.Container',
      'method': action,
      'name': '"$name"',
      'version': 1,
      '_sid': _sid,
    };
    if (action == 'signal') data['signal'] = 9;
    if (action == 'delete' && preserveProfile != null) data['preserve_profile'] = preserveProfile;
    return await post('entry.cgi', data: data);
  }

  /// Docker 日志
  Future<Map> dockerLog(String name, String method, {String? date}) async {
    final data = {
      'api': 'SYNO.Docker.Container.Log',
      'method': method,
      'name': '"$name"',
      'version': 1,
      '_sid': _sid,
    };
    if (method == 'get') {
      data['sort_dir'] = '"ASC"';
      data['date'] = '"$date"';
      data['limit'] = 1000;
      data['offset'] = 0;
    }
    return await post('entry.cgi', data: data);
  }

  // ==================== 套件中心 ====================

  /// 已安装套件
  Future<Map> installedPackages({int version = 1}) async {
    final additional = [
      'description', 'description_enu', 'beta', 'distributor',
      'distributor_url', 'maintainer', 'maintainer_url', 'dsm_apps',
      'report_beta_url', 'support_center', 'startable', 'installed_info',
      'support_url', 'is_uninstall_pages', 'install_type', 'autoupdate',
      'silent_upgrade', 'installing_progress', 'ctl_uninstall', 'status', 'url',
    ];
    if (version == 2) additional.add('updated_at');
    return await post('entry.cgi', data: {
      'additional': jsonEncode(additional),
      'polling_interval': 15,
      'api': 'SYNO.Core.Package',
      'version': version,
      'method': 'list',
      '_sid': _sid,
    });
  }

  /// 可用套件
  Future<Map> packages({bool others = false, int version = 1}) async {
    return await post('entry.cgi', data: {
      'updateSprite': true,
      'blforcereload': false,
      'blloadothers': others,
      'api': 'SYNO.Core.Package.Server',
      'version': version,
      'method': 'list',
      '_sid': _sid,
    });
  }

  /// 套件操作 (启动/停止)
  Future<Map> launchPackage(String id, String app, String method) async {
    final data = {
      'id': id,
      'api': 'SYNO.Core.Package.Control',
      'version': 1,
      'method': method,
      '_sid': _sid,
    };
    if (method == 'start') {
      data['dsm_apps'] = jsonEncode([app]);
    }
    return await post('entry.cgi', data: data);
  }

  /// 卸载套件
  Future<Map> uninstallPackageTask(String id, {Map? extra}) async {
    final data = {
      'id': id,
      'api': 'SYNO.Core.Package.Uninstallation',
      'version': 1,
      'method': 'uninstall',
      '_sid': _sid,
    };
    if (extra != null) {
      data['extra_values'] = jsonEncode(jsonEncode(extra));
    }
    return await post('entry.cgi', data: data);
  }

  // ==================== 用户管理 ====================

  /// 用户列表
  Future<Map> users() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.User',
      'offset': 0,
      'limit': -1,
      'additional': jsonEncode(['email', 'description', 'expired']),
      'version': 1,
      'method': 'list',
      '_sid': _sid,
    });
  }

  /// 用户组列表
  Future<Map> userGroups() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.Group',
      'offset': 0,
      'limit': -1,
      'name_only': false,
      'version': 1,
      'method': 'list',
      '_sid': _sid,
    });
  }

  /// 当前登录用户信息 (SYNO.Core.NormalUser)
  /// [method] 'get' 获取 / 'set' 修改
  Future<Map> normalUser(String method, {Map<String, dynamic>? changedData}) async {
    final data = <String, dynamic>{
      'api': 'SYNO.Core.NormalUser',
      'method': method,
      'version': method == 'get' ? 1 : 2,
      '_sid': _sid,
    };
    if (changedData != null) {
      final save = <String, dynamic>{};
      changedData.forEach((k, v) {
        if (v is String && v.isNotEmpty && k != 'confirm_password') {
          save[k] = v;
        } else if (v is bool) {
          save[k] = v;
        }
      });
      data['data'] = jsonEncode(jsonEncode(save));
    }
    return await post('entry.cgi', data: data);
  }

  // ==================== 共享文件夹管理 ====================

  /// 共享文件夹列表 (Core)
  Future<Map> shareCore({List<String> additional = const []}) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.Share"',
      'method': '"list"',
      'version': 1,
      '_sid': _sid,
      'shareType': '"all"',
      'additional': jsonEncode(additional),
    });
  }

  /// 删除共享文件夹
  Future<Map> deleteSharedFolder(List<String> names) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.Share"',
      'method': '"delete"',
      'version': 1,
      '_sid': _sid,
      'name': jsonEncode(names),
    });
  }

  /// 清空回收站
  Future<Map> cleanRecycleBin(String id) async {
    return await post('entry.cgi', data: {
      id: '"$id"',
      'api': '"SYNO.Core.RecycleBin"',
      'method': 'start',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 卷列表
  Future<Map> volumes() async {
    return await post('entry.cgi', data: {
      'limit': -1,
      'offset': 0,
      'location': '"internal"',
      'api': 'SYNO.Core.Storage.Volume',
      'version': 1,
      'method': 'list',
      '_sid': _sid,
    });
  }

  // ==================== 控制面板 ====================

  /// SSH/Telnet 设置
  Future<Map> terminalInfo() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.Terminal',
      'version': 3,
      'method': 'get',
      '_sid': _sid,
    });
  }

  /// 设置 SSH/Telnet
  Future<Map> setTerminal(bool ssh, bool telnet, String sshPort) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.Terminal"',
      'enable_telnet': telnet,
      'enable_ssh': ssh,
      'ssh_port': sshPort,
      'version': 3,
      'method': 'set',
      '_sid': _sid,
    });
  }

  /// 任务计划列表
  Future<Map> taskScheduler() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.TaskScheduler',
      'offset': 0,
      'limit': -1,
      'sort_by': 'next_trigger_time',
      'sort_direction': 'DESC',
      'version': 1,
      'method': 'list',
      '_sid': _sid,
    });
  }

  /// 运行任务计划
  Future<Map> taskRun(List<int> task) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.TaskScheduler',
      'version': 1,
      'method': 'run',
      'task': jsonEncode(task),
      '_sid': _sid,
    });
  }

  /// 启用/禁用任务计划
  Future<Map> taskEnable(int task, bool enable) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.TaskScheduler',
      'version': 1,
      'method': 'set_enable',
      'status': jsonEncode([
        {'id': task, 'enable': enable}
      ]),
      '_sid': _sid,
    });
  }

  /// 任务记录
  Future<Map> taskRecord(int task) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.TaskScheduler',
      'version': 1,
      'offset': 0,
      'limit': 2,
      'method': 'view',
      'id': task,
      '_sid': _sid,
    });
  }

  /// 媒体索引
  Future<Map> mediaConverter(String method, {int? hours}) async {
    final data = {
      'api': 'SYNO.Core.MediaIndexing.MediaConverter',
      'method': method,
      'version': 1,
    };
    if (hours != null) data['delay_hours'] = hours;
    return await post('entry.cgi', data: data);
  }

  // ==================== 日志 ====================

  /// 最近日志
  Future<Map> lastLog(int start, int limit) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.SyslogClient.Status',
      'start': start,
      'limit': limit,
      'method': 'latestlog_get',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 日志列表
  Future<Map> log(
    int start,
    int limit, {
    String target = 'LOCAL',
    String logType = 'system,netbackup',
  }) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.SyslogClient.Log',
      'start': start,
      'limit': limit,
      'target': target,
      'logtype': logType,
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 文件传输日志
  Future<Map> fileTransferLog(int start, int limit) async {
    return await post('entry.cgi', data: {
      'start': start,
      'limit': limit,
      'target': 'LOCAL',
      'logtype': 'ftp,filestation,webdav,cifs,tftp,afp',
      'dir': 'desc',
      'api': 'SYNO.Core.SyslogClient.Log',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 日志历史
  Future<Map> logHistory() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.LogCenter.History',
      'offset': 0,
      'limit': 50,
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  // ==================== 虚拟机 ====================

  /// 集群信息
  Future<Map> cluster(String method) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Virtualization.Cluster',
      'method': method,
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 虚拟机电源
  Future<Map> vmmPower(String guestId, String action) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Virtualization.Guest.Action"',
      'method': '"pwr_ctl"',
      'guest_id': '"$guestId"',
      'action': action,
      'version': 1,
      '_sid': _sid,
    });
  }

  // ==================== 安全扫描 ====================

  /// 安全扫描状态
  Future<Map> securityScanStatus() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.SecurityScan.Status',
      'method': 'get',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 安全扫描 - 获取规则列表
  Future<Map> securityRuleGet() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.SecurityScan.Status',
      'method': 'rule_get',
      'items': '"ALL"',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 安全扫描 - 获取系统状态
  Future<Map> securitySystemGet() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.SecurityScan.Status',
      'method': 'system_get',
      'version': 1,
      '_sid': _sid,
    });
  }

  // ==================== 存储管理 ====================

  /// SMART 数据
  Future<Map> smartData(String deviceId) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Storage.CGI.Smart',
      'method': 'get_health_info',
      'version': 1,
      'device': '"$deviceId"',
      '_sid': _sid,
    });
  }

  /// 磁盘信息
  Future<Map> diskInfo() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.Storage.Disk',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  // ==================== 工具方法 ====================

  /// 对群晖 DSM 网页 URL 追加 SynoToken 以实现自动登录
  /// 仅当 URL 属于当前服务器且已有 SynoToken 时追加
  String resolveUrlWithAuth(String url) {
    if (_synoToken.isEmpty) return url;
    final host = _server?.host ?? '';
    if (host.isEmpty) return url;

    // 检查 URL 是否属于当前服务器
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (!uri.host.contains(host) && !host.contains(uri.host)) return url;

    // 已有 SynoToken 参数则不重复添加
    if (uri.queryParameters.containsKey('SynoToken')) return url;

    final separator = uri.query.isNotEmpty ? '&' : '?';
    return '$url${separator}SynoToken=$_synoToken';
  }

  /// 格式化文件大小
  static String formatSize(num size, {int format = 1024, int fixed = 2}) {
    if (size == 0) return '0';
    if (size < format) return '$size';
    if (size < pow(format, 2)) {
      return '${(size / format).toStringAsFixed(fixed)}K';
    }
    if (size < pow(format, 3)) {
      return '${(size / pow(format, 2)).toStringAsFixed(fixed)}M';
    }
    if (size < pow(format, 4)) {
      return '${(size / pow(format, 3)).toStringAsFixed(fixed)}G';
    }
    return '${(size / pow(format, 4)).toStringAsFixed(fixed)}T';
  }

  /// 文件类型枚举
  static FileTypeEnum fileType(String name) {
    final ext = name.split('.').last.toLowerCase();
    const image = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'ico', 'tiff', 'tif', 'webp', 'heic'];
    const movie = [
      '3gp', 'asf', 'dat', 'divx', 'm2t', 'm2ts', 'm4v', 'mkv', 'mp4',
      'mts', 'mov', 'qt', 'tp', 'trp', 'ts', 'vob', 'wmv', 'xvid', 'rm',
      'rmvb', 'mpeg', 'mpg', 'ogv', 'webm', 'flv', 'avi', 'swf'
    ];
    const music = [
      'aac', 'flac', 'm4a', 'm4b', 'aif', 'ogg', 'pcm', 'wav', 'mid',
      'mp2', 'mka', 'mpc', 'ape', 'ra', 'dts', 'wma', 'mp3', 'aiff'
    ];
    const word = ['doc', 'docx'];
    const ppt = ['ppt', 'pptx'];
    const excel = ['xls', 'xlsx'];
    const text = ['txt', 'log'];
    const zip = ['zip', 'gz', 'tar', 'tgz', 'tbz', 'bz2', 'rar', '7z'];
    const code = [
      'py', 'php', 'c', 'java', 'jsp', 'js', 'css', 'sql', 'nfo', 'xml',
      'kt', 'conf', 'json', 'md', 'sh', 'ts', 'dart', 'swift'
    ];
    const pdf = ['pdf'];
    const apk = ['apk'];
    const iso = ['iso'];

    if (image.contains(ext)) return FileTypeEnum.image;
    if (movie.contains(ext)) return FileTypeEnum.movie;
    if (music.contains(ext)) return FileTypeEnum.music;
    if (word.contains(ext)) return FileTypeEnum.word;
    if (ppt.contains(ext)) return FileTypeEnum.ppt;
    if (excel.contains(ext)) return FileTypeEnum.excel;
    if (text.contains(ext)) return FileTypeEnum.text;
    if (zip.contains(ext)) return FileTypeEnum.zip;
    if (code.contains(ext)) return FileTypeEnum.code;
    if (pdf.contains(ext)) return FileTypeEnum.pdf;
    if (apk.contains(ext)) return FileTypeEnum.apk;
    if (iso.contains(ext)) return FileTypeEnum.iso;
    return FileTypeEnum.other;
  }

  /// 解析 DSM 版本
  static int parseDsmVersion(String versionString) {
    final index = versionString.indexOf('DSM');
    if (index == -1) return 7;
    final ver = versionString.substring(index + 4);
    return int.tryParse(ver.split('.').first) ?? 7;
  }

  /// 解析运行时间
  static String parseUpTime(String optime) {
    final items = optime.split(':');
    final days = int.parse(items[0]) ~/ 24;
    items[0] = (int.parse(items[0]) % 24).toString().padLeft(2, '0');
    items[1] = items[1].toString().padLeft(2, '0');
    items[2] = items[2].toString().padLeft(2, '0');
    return '${days > 0 ? "${days}天 " : ""}${items.join(':')}';
  }

  // ==================== 照片备份 ====================

  /// 检测照片是否需要备份 (backup_check)
  Future<Map> fotoBackupCheck(List<Map> checkItems) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Foto.Upload.Item',
      'method': 'backup_check',
      'version': 7,
      '_sid': _sid,
      'check': jsonEncode(checkItems),
    });
  }

  /// 上传备份照片 (backup_to_path)
  Future<Map> fotoBackupUpload({
    required String filePath,
    required String fileName,
    required int mtime,
    required List<String> targetFolderPath,
    required List<String> subfolder,
    required String similarHash,
    String duplicate = 'ignore',
    String? thumbSmPath,
    String? thumbXlPath,
  }) async {
    final data = <String, dynamic>{
      'api': 'SYNO.Foto.Upload.Item',
      'method': 'backup_to_path',
      'version': 7,
      '_sid': _sid,
      'name': jsonEncode(fileName),
      'mtime': mtime,
      'target_folder_path': jsonEncode(targetFolderPath),
      'subfolder': jsonEncode(subfolder),
      'duplicate': jsonEncode(duplicate),
      'require_thumb_version': true,
      'model_version': 3,
      'similar_hash': jsonEncode(similarHash),
    };

    // Attach files
    data['file'] = await MultipartFile.fromFile(filePath, filename: fileName);

    if (thumbSmPath != null && await File(thumbSmPath).exists()) {
      data['thumb_sm'] = await MultipartFile.fromFile(thumbSmPath, filename: 'sm');
    }
    if (thumbXlPath != null && await File(thumbXlPath).exists()) {
      data['thumb_xl'] = await MultipartFile.fromFile(thumbXlPath, filename: 'xl');
    }

    return await upload('entry.cgi', data: data);
  }

  // ==================== 迁移补充 API (begin) ====================
  // 以下方法严格按旧版 refer_demo/dsm_helper/lib/util/api.dart 忠实迁移，
  // 仅适配新版调用约定(post / _sid / 空安全)，api/method/version 保持一致。

  /// 内部：格式化 DateTime 为 "yyyy-MM-dd HH:mm:ss"
  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  // -------- 共享文件夹 / 挂载 / 远程连接 --------

  /// 共享文件夹详情
  Future<Map> shareDetail(String name) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.Share"',
      'method': '"get"',
      'version': 1,
      '_sid': _sid,
      'name': '"$name"',
      'additional': jsonEncode([
        'hidden', 'recyclebin', 'advance_setting', 'encryption',
        'is_cluster_share', 'is_cold_storage_share', 'enable_snapshot_browsing',
        'share_quota', 'enable_share_cow', 'enable_share_compress',
      ]),
    });
  }

  /// 新建 / 编辑共享文件夹
  Future<Map> addSharedFolder(
    String name,
    String volPath,
    String desc, {
    String? oldName,
    bool encryption = false,
    String password = '',
    bool recycleBin = false,
    bool recycleBinAdminOnly = false,
    bool hidden = false,
    bool hideUnreadable = false,
    bool enableShareCow = false,
    bool enableShareCompress = false,
    bool enableShareQuota = false,
    String shareQuota = '',
    String method = 'create',
  }) async {
    final Map shareInfo = {
      'name': name,
      'vol_path': volPath,
      'desc': desc,
      'name_org': '',
      'enable_recycle_bin': recycleBin,
      'recycle_bin_admin_only': recycleBinAdminOnly,
      'encryption': encryption,
      'hidden': hidden,
      'hide_unreadable': hideUnreadable,
      'enable_share_cow': enableShareCow,
      'enable_share_compress': enableShareCow && enableShareCompress,
    };
    if (encryption) {
      shareInfo['enc_passwd'] = password;
    }
    shareInfo['share_quota'] = enableShareQuota ? num.parse(shareQuota) : 0;
    return await post('entry.cgi', data: {
      'api': '"SYNO.Core.Share"',
      'method': '"$method"',
      'version': 1,
      '_sid': _sid,
      'name': oldName ?? name,
      'shareinfo': jsonEncode(shareInfo),
    });
  }

  /// 编辑共享链接
  Future<Map> editShare(
    String path,
    List<String> id,
    List<String> url,
    DateTime? dateExpired,
    DateTime? dateAvailabe,
    String? expireTimes, {
    bool fileRequest = false,
    String? requestName,
    String? requestInfo,
  }) async {
    final Map<String, dynamic> data = {
      'path': path,
      'url': jsonEncode(url),
      'protect_type_enable': '"false"',
      'date_expired': dateExpired == null ? '' : '"${_fmtDateTime(dateExpired)}"',
      'expire_times': expireTimes ?? '',
      'protect_type': 'none',
      'redirect_uri': null,
      'id': jsonEncode(id),
      'date_available': dateAvailabe == null ? '' : '"${_fmtDateTime(dateAvailabe)}"',
      'api': '"SYNO.FileStation.Sharing"',
      'method': '"edit"',
      'version': 3,
      '_sid': _sid,
    };
    if (fileRequest) {
      data['file_request'] = true;
      data['request_name'] = requestName;
      data['request_info'] = requestInfo;
    }
    return await post('entry.cgi', data: data);
  }

  /// SMB/NFS 远程文件夹列表
  Future<Map> smbFolder() async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.VirtualFolder"',
      'method': '"list"',
      'version': 2,
      '_sid': _sid,
      'node': 'fm_rf_root',
      'type': '["cifs","nfs"]',
      'additional': '["real_path","owner","time","perm","mount_point_type","volume_status"]',
    });
  }

  /// 远程连接（虚拟文件夹）列表
  Future<Map> remoteLink(String type) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.FileStation.VirtualFolder',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
      'node': '"$type"',
      'type': '"$type"',
      'sort_by': '"name"',
      'additional': '["real_path","owner","time","perm","mount_point_type","volume_status"]',
    });
  }

  /// 断开远程连接
  Future<Map> remoteUnConnect(String id) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.VFS.Connection"',
      'method': '"delete"',
      'version': 1,
      '_sid': _sid,
      'id': '"$id"',
    });
  }

  /// 挂载远程文件夹（CIFS）
  Future<Map> mountFolder(String serverIp, String account, String passwd, String mountPoint, bool autoMount) async {
    return await post('entry.cgi', data: {
      'mount_type': '"CIFS"',
      'server_ip': jsonEncode(serverIp),
      'mount_point': '"$mountPoint"',
      'user_set': false,
      'auto_mount': autoMount,
      'adv_opt': '""',
      'account': '"$account"',
      'passwd': '"$passwd"',
      'api': 'SYNO.FileStation.Mount',
      'method': 'mount_remote',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 卸载远程文件夹
  Future<Map> unMountFolder(String path) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Mount"',
      'method': '"unmount"',
      'version': 1,
      '_sid': _sid,
      'mount_point': '"$path"',
      'is_mount_point': true,
      'mount_type': '"remote"',
    });
  }

  /// 上传前检查目标路径写权限
  Future<Map> checkPermission(String uploadPath, String filePath) async {
    final file = File(filePath);
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.CheckPermission"',
      'method': '"write"',
      'version': 3,
      'overwrite': 'false',
      'filename': filePath.split('/').last,
      'path': uploadPath,
      'size': await file.length(),
      '_sid': _sid,
    });
  }

  /// 压缩任务状态
  Future<Map> compressResult(String taskId) async {
    return await post('entry.cgi', data: {
      'taskid': taskId,
      'api': '"SYNO.FileStation.Compress"',
      'method': '"status"',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 解压任务状态
  Future<Map> extractResult(String taskId) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.FileStation.Extract"',
      'method': '"status"',
      'version': 1,
      '_sid': _sid,
      'taskid': taskId,
    });
  }

  // -------- DDNS / 网络 / 固件 --------

  /// DDNS 保存
  Future<Map> ddnsSave(Map ddns) async {
    final Map<String, dynamic> data = {
      'api': 'SYNO.Core.DDNS.Record',
      'method': 'set',
      'version': 1,
      'id': '"${ddns['id'].replaceAll("USER_", "*")}"',
      'enable': ddns['enable'],
      'provider': '"${ddns['provider']}"',
      'hostname': '"${ddns['hostname']}"',
      'username': '"${ddns['username']}"',
      'net': '"${ddns['net']}"',
      'ip': '"${ddns['ip']}"',
      'ipv6': '"${ddns['ipv6']}"',
      'heartbeat': ddns['heartbeat'],
      '_sid': _sid,
    };
    if (ddns['passwd'] != null) {
      data['passwd'] = '"${ddns['passwd']}"';
    }
    return await post('entry.cgi', data: data);
  }

  /// DDNS 立即更新 IP
  Future<Map> ddnsUpdate({String? id}) async {
    final Map<String, dynamic> data = {
      'api': 'SYNO.Core.DDNS.Record',
      'method': 'update_ip_address',
      'version': 1,
      '_sid': _sid,
    };
    if (id != null) {
      data['id'] = '"$id"';
    }
    return await post('entry.cgi', data: data);
  }

  /// DDNS 删除
  Future<Map> ddnsDelete(String id) async {
    return await post('entry.cgi', data: {
      'id': jsonEncode(['$id']),
      'api': 'SYNO.Core.DDNS.Record',
      'method': 'delete',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// DDNS 测试
  Future<Map> ddnsTest(Map ddns) async {
    final Map<String, dynamic> data = {
      'api': 'SYNO.Core.DDNS.Record',
      'method': 'test',
      'version': 1,
      'heartbeat': ddns['heartbeat'],
      'enable': true,
      'provider': '"${ddns['provider'].replaceAll("*", "USER_")}"',
      'hostname': '"${ddns['hostname']}"',
      'username': '"${ddns['username']}"',
      'net': '"${ddns['net']}"',
      'ip': '"${ddns['ip']}"',
      'ipv6': '"${ddns['ipv6']}"',
      '_sid': _sid,
    };
    if (ddns['passwd'] != null) {
      data['passwd'] = '"${ddns['passwd']}"';
    }
    return await post('entry.cgi', data: data);
  }

  /// 外部访问信息（DDNS 概览，批量 parallel）
  Future<Map> publicAccessInfo() async {
    final apis = [
      {'api': 'SYNO.Core.DDNS.Provider', 'version': 1, 'method': 'list'},
      {'api': 'SYNO.Core.DDNS.Record', 'version': 1, 'method': 'list'},
      {'api': 'SYNO.Core.DDNS.ExtIP', 'version': 2, 'method': 'list', 'retry': true},
      {'api': 'SYNO.Core.DDNS.Synology', 'version': 1, 'method': 'get_myds_account'},
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"parallel"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 固件版本信息
  Future<Map> firmwareVersion() async {
    return await post('entry.cgi', data: {
      'type': '"firmware"',
      'api': 'SYNO.Core.System',
      'method': 'info',
      'version': 3,
      '_sid': _sid,
    });
  }

  /// 检查固件更新
  Future<Map> firmwareUpgrade() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.Upgrade.Server',
      'method': 'check',
      'version': 2,
      'user_reading': true,
      'need_auto_smallupdate': true,
      'need_promotion': true,
      '_sid': _sid,
    });
  }

  /// 网络状态（批量 sequential）
  Future<Map> networkStatus() async {
    // 旧版此处对 SYNO.Core.Network 取 min(minVersion,2)，实测 minVersion 通常为 1，此处固定 1
    final apis = [
      {'api': 'SYNO.Core.Network', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Network.Ethernet', 'method': 'list', 'version': 2},
      {'api': 'SYNO.Core.Network.PPPoE', 'method': 'list', 'version': 1},
      {'api': 'SYNO.Core.Network.Proxy', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Network.Router.Gateway.List', 'method': 'get', 'version': 1, 'iptype': 'ipv4', 'type': 'wan'},
      {'api': 'SYNO.Core.Web.DSM', 'method': 'get', 'version': 2},
    ];
    return await post('entry.cgi', data: {
      'stop_when_error': false,
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }
  // -------- 下载 (DownloadStation2) --------

  /// BT/离线下载：获取待下载文件列表
  Future<Map> downloadFileList(String listId) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.List',
      'list_id': listId,
      'method': 'get',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 根据文件列表创建下载任务
  Future<Map> downloadCreate(String listId, String destination, List selectedFile) async {
    final dest = destination.substring(1);
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.List.Polling',
      'destination': '"$dest"',
      'list_id': '"$listId"',
      'selected': jsonEncode(selectedFile),
      'method': 'download',
      'create_subfolder': true,
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 下载任务详情 (detail + transfer)
  Future<Map> downloadDetail(String id) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task',
      'id': jsonEncode([id]),
      'additional': jsonEncode(['detail', 'transfer']),
      'method': 'get',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// BT 任务的 Tracker 列表
  Future<Map> downloadTracker(String id) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.BT.Tracker',
      'task_id': '"$id"',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 为 BT 任务添加 Tracker
  Future<Map> downloadTrackerAdd(String id, List<String> trackers) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.BT.Tracker',
      'task_id': '"$id"',
      'method': 'add',
      'tracker': jsonEncode(trackers),
      'version': 2,
      '_sid': _sid,
    });
  }

  /// BT 任务的 Peer 列表
  Future<Map> downloadPeer(String id) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.BT.Peer',
      'task_id': '"$id"',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// BT 任务内的文件列表
  Future<Map> downloadFile(String id) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.DownloadStation2.Task.BT.File',
      'offset': 0,
      'limit': 50,
      'sort_by': 'name',
      'order': 'ASC',
      'query': '',
      'task_id': '"$id"',
      'method': 'list',
      'version': 2,
      '_sid': _sid,
    });
  }

  // -------- 存储 / 磁盘 / 外接设备 --------

  /// 磁盘 S.M.A.R.T. 健康信息
  Future<Map> smart(String device) async {
    return await post('entry.cgi', data: {
      'device': '"$device"',
      'api': 'SYNO.Storage.CGI.Smart',
      'method': 'get_health_info',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 磁盘检测日志
  Future<Map> diskTestLog(String device) async {
    return await post('entry.cgi', data: {
      'sort_by': '"time"',
      'sort_direction': '"DESC"',
      'offset': 0,
      'limit': 30,
      'type': '"all"',
      'device': '"$device"',
      'api': 'SYNO.Core.Storage.Disk',
      'method': 'disk_test_log_get',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// S.M.A.R.T. 检测日志
  Future<Map> smartTestLog(String device) async {
    return await post('entry.cgi', data: {
      'device': '"$device"',
      'api': 'SYNO.Core.Storage.Disk',
      'method': 'get_smart_test_log',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 发起 S.M.A.R.T. 检测 (type: quick/extend)
  Future<Map> doSmartTest(String device, String type) async {
    return await post('entry.cgi', data: {
      'device': '"$device"',
      'type': '"$type"',
      'api': 'SYNO.Core.Storage.Disk',
      'method': 'do_smart_test',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 外接存储设备列表 (USB + eSATA, 复合请求)
  Future<Map> externalDevice() async {
    final apis = [
      {'api': 'SYNO.Core.ExternalDevice.Storage.USB', 'method': 'list', 'version': 1, 'additional': ['all']},
      {'api': 'SYNO.Core.ExternalDevice.Storage.eSATA', 'method': 'list', 'version': 1, 'additional': ['all']},
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 弹出 eSATA 设备
  Future<Map> ejectEsata(String id) async {
    return await post('entry.cgi', data: {
      'dev_id': '"$id"',
      'api': 'SYNO.Core.ExternalDevice.Storage.eSATA',
      'method': 'eject',
      'version': 1,
      '_sid': _sid,
    });
  }

  // -------- 电源 / 硬件 --------

  /// 电源与硬件状态汇总 (复合请求)
  Future<Map> powerStatus() async {
    final apis = [
      {'api': 'SYNO.Core.Hardware.ZRAM', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.PowerRecovery', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.BeepControl', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.FanSpeed', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.Led.Brightness', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.Hibernation', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.ExternalDevice.UPS', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Hardware.PowerSchedule', 'method': 'load', 'version': 1},
    ];
    return await post('entry.cgi', data: {
      'stop_when_error': false,
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 保存开关机计划
  Future<Map> powerScheduleSave(List powerOns, List powerOffs) async {
    return await post('entry.cgi', data: {
      'poweron_tasks': jsonEncode(powerOns),
      'poweroff_tasks': jsonEncode(powerOffs),
      'api': 'SYNO.Core.Hardware.PowerSchedule',
      'method': 'save',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 保存电源相关设置 (ZRAM/电源恢复/蜂鸣/风扇/LED, 复合请求)
  Future<Map> powerSet(bool enableZram, Map? powerRecovery, Map? beepControl, Map? fanSpeed, Map? led) async {
    final apis = <Map>[
      {'api': 'SYNO.Core.Hardware.ZRAM', 'method': 'set', 'version': '1', 'enable_zram': enableZram},
    ];
    if (powerRecovery != null) {
      apis.add({'api': 'SYNO.Core.Hardware.PowerRecovery', 'method': 'set', 'version': '1', 'rc_power_config': powerRecovery['rc_power_config'], 'wol1': powerRecovery['wol1'] ?? false, 'wol2': powerRecovery['wol2'] ?? false});
    }
    if (beepControl != null) {
      apis.add({'api': 'SYNO.Core.Hardware.BeepControl', 'method': 'set', 'version': '1', 'fan_fail': beepControl['fan_fail'] ?? false, 'volume_crash': beepControl['volume_crash'] ?? false, 'ssd_cache_crash': beepControl['ssd_cache_crash'] ?? false, 'poweron_beep': beepControl['poweron_beep'] ?? false, 'poweroff_beep': beepControl['poweroff_beep'] ?? false});
    }
    if (fanSpeed != null) {
      apis.add({'api': 'SYNO.Core.Hardware.FanSpeed', 'method': 'set', 'version': '1', 'dual_fan_speed': fanSpeed['dual_fan_speed']});
    }
    if (led != null) {
      apis.add({'api': 'SYNO.Core.Hardware.Led.Brightness', 'method': 'set', 'version': '1', 'led_brightness': led['led_brightness'], 'schedule': led['schedule']});
    }
    return await post('entry.cgi', data: {
      'stop_when_error': false,
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 保存硬盘休眠设置
  Future<Map> powerHibernationSave({int? internalHdIdletime, bool? sataDeepSleep, int? usbIdletime, bool? enableLog, bool? autoPoweroffEnable, int? autoPoweroffTime}) async {
    return await post('entry.cgi', data: {
      'internal_hd_idletime': internalHdIdletime,
      'sata_deep_sleep': sataDeepSleep,
      'ignore_netbios_broadcast': false,
      'usb_idletime': usbIdletime,
      'enable_log': enableLog,
      'auto_poweroff_enable': autoPoweroffEnable,
      'auto_poweroff_time': autoPoweroffTime,
      'api': 'SYNO.Core.Hardware.Hibernation',
      'method': 'set',
      'version': 1,
      '_sid': _sid,
    });
  }

  // -------- 套件 (Package) --------

  /// 已启动套件轮询数据
  Future<Map> launchedPackages() async {
    return await post('entry.cgi', data: {
      'action': 'load',
      'load_disabled_port': true,
      'api': 'SYNO.Core.Polling.Data',
      'version': 1,
      'method': 'get',
      '_sid': _sid,
    });
  }

  /// 安装套件任务
  Future<Map> installPackageTask(String name, String path) async {
    return await post('entry.cgi', data: {
      'name': name,
      'blqinst': true,
      'volume_path': path,
      'is_syno': true,
      'beta': false,
      'installrunpackage': true,
      'api': 'SYNO.Core.Package.Installation',
      'version': 1,
      'method': 'install',
      '_sid': _sid,
    });
  }

  /// 套件安装状态
  Future<Map> installPackageStatus(String taskId) async {
    return await post('entry.cgi', data: {
      'task_id': taskId,
      'api': 'SYNO.Core.Package.Installation',
      'version': 1,
      'method': 'status',
      '_sid': _sid,
    });
  }

  /// 套件安装队列
  Future<Map> installPackageQueue(String pkg, String version, {bool beta = false}) async {
    return await post('entry.cgi', data: {
      'pkgs': '[{"pkg":"$pkg", "version": "$version","beta":$beta}]',
      'api': 'SYNO.Core.Package.Installation',
      'version': 1,
      'method': 'get_queue',
      '_sid': _sid,
    });
  }

  /// 卸载套件前的信息查询
  Future<Map> uninstallPackageInfo(String id) async {
    return await post('entry.cgi', data: {
      'id': id,
      'additional': jsonEncode(['uninstall_pages']),
      'api': 'SYNO.Core.Package',
      'version': 1,
      'method': 'get',
      '_sid': _sid,
    });
  }

  // -------- 用户 / 群组 / OTP --------

  /// 用户详情 (账号/权限/配额等, 复合请求)
  Future<Map> userDetail(String name) async {
    final apis = [
      {'api': 'SYNO.Core.User', 'method': 'get', 'version': 1, 'name': name, 'additional': ['description', 'email', 'expired', 'cannot_chg_passwd', 'passwd_never_expire']},
      {'api': 'SYNO.Core.User.PasswordExpiry', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Share.Permission', 'method': 'list_by_user', 'version': 1, 'name': name, 'user_group_type': 'local_user', 'share_type': ['dec', 'local', 'usb', 'sata', 'cluster', 'cold_storage'], 'additional': ['hidden', 'encryption', 'is_aclmode']},
      {'api': 'SYNO.Core.Storage.Volume', 'method': 'list', 'version': 1, 'offset': 0, 'limit': -1, 'location': 'internal'},
      {'api': 'SYNO.Core.BandwidthControl', 'method': 'get', 'version': 2, 'name': name, 'owner_type': 'local_user'},
      {'api': 'SYNO.Core.OTP.Admin', 'method': 'get', 'version': 1, 'name': name},
      {'api': 'SYNO.Core.FileServ.SMB', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.Quota', 'method': 'get', 'version': 1, 'name': name, 'support_share_quota': true},
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 保存用户信息并同步群组成员 (复合请求)
  Future<Map> userSave(Map userInfo, List addGroup, List removeGroup) async {
    final userInfoApi = <String, dynamic>{
      'api': 'SYNO.Core.User',
      'method': 'set',
      'version': 1,
      'name': userInfo['name'],
      'description': userInfo['description'],
      'email': userInfo['email'],
      'cannot_chg_passwd': userInfo['cannot_chg_passwd'],
      'expired': userInfo['expired'],
      'new_name': userInfo['new_name'],
    };
    if (userInfo['password'] != null && (userInfo['password'] as String).isNotEmpty) {
      userInfoApi['password'] = userInfo['password'];
    }
    final apis = <Map>[userInfoApi];
    for (int i = 0; i < addGroup.length; i++) {
      apis.add({'api': 'SYNO.Core.Group.Member', 'method': 'add', 'version': 1, 'group': addGroup[i], 'name': userInfo['name']});
    }
    for (int i = 0; i < removeGroup.length; i++) {
      apis.add({'api': 'SYNO.Core.Group.Member', 'method': 'remove', 'version': 1, 'group': removeGroup[i], 'name': userInfo['name']});
    }
    return await post('entry.cgi', data: {
      'stop_when_error': false,
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 查询用户所属群组
  Future<Map> userGroup(String name) async {
    return await post('entry.cgi', data: {
      'name_only': false,
      'user': '"$name"',
      'type': '"local"',
      'api': 'SYNO.Core.Group',
      'method': 'list',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 当前用户配额
  Future<Map> userQuota() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.PersonalSettings',
      'method': 'quota',
      'version': 1,
    });
  }

  /// 保存用户个性化设置 (data 为二次 JSON 编码字符串)
  Future<Map> userSetting(Map save) async {
    final dataStr = jsonEncode(jsonEncode(save));
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.UserSettings',
      'data': dataStr,
      'method': 'apply',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 获取 OTP 二维码
  Future<Map> getQrCode(String account) async {
    return await post('entry.cgi', data: {
      'account': '"$account"',
      'api': 'SYNO.Core.OTP',
      'method': 'get_qrcode',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 保存 OTP 恢复邮箱
  Future<Map> saveMail(String mail) async {
    return await post('entry.cgi', data: {
      'mail': '"$mail"',
      'api': 'SYNO.Core.OTP',
      'method': 'save_mail',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 校验 OTP 临时码
  Future<Map> authOtpCode(String code) async {
    return await post('entry.cgi', data: {
      'code': '"$code"',
      'api': 'SYNO.Core.OTP',
      'method': 'auth_tmp_code',
      'version': 2,
      '_sid': _sid,
    });
  }

  /// 信任设备管理 (method 由调用方指定)
  Future<Map> trustDevice(String method) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.TrustDevice',
      'method': method,
      'version': 1,
      '_sid': _sid,
    });
  }

  // -------- 文件服务 (SMB/AFP/NFS/FTP) --------

  /// 文件服务总览 (复合请求)
  Future<Map> fileService() async {
    final apis = [
      {'api': 'SYNO.Core.FileServ.SMB', 'method': 'get', 'version': 3},
      {'api': 'SYNO.Core.FileServ.AFP', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.FileServ.NFS', 'method': 'get', 'version': 2},
      {'api': 'SYNO.Core.FileServ.FTP', 'method': 'get', 'version': 3},
      {'api': 'SYNO.Core.FileServ.FTP.SFTP', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.SyslogClient.FileTransfer', 'method': 'get', 'version': 1},
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 查询文件服务日志级别
  Future<Map> fileServiceLog(String protocol) async {
    return await post('entry.cgi', data: {
      'protocol': '"$protocol"',
      'api': 'SYNO.Core.SyslogClient.FileTransfer',
      'method': 'get_level',
      'version': 1,
    });
  }

  /// 保存文件服务日志级别
  Future<Map> fileServiceLogSave(String protocol, Map logLevel) async {
    return await post('entry.cgi', data: {
      'protocol': '"$protocol"',
      'loglevel': jsonEncode(logLevel),
      'api': 'SYNO.Core.SyslogClient.FileTransfer',
      'method': 'set_level',
      'version': 1,
    });
  }

  /// 保存文件服务设置 (SMB/AFP/NFS/FTP/SFTP, 复合请求)
  Future<Map> fileServiceSave(Map smb, Map syslogClient, Map afp, Map nfs, Map ftp, Map sftp) async {
    final apis = [
      {'api': 'SYNO.Core.FileServ.SMB', 'method': 'set', 'version': 3, 'enable_samba': smb['enable_samba'], 'workgroup': smb['workgroup'], 'disable_shadow_copy': smb['disable_shadow_copy'], 'smb_transfer_log_enable': syslogClient['cifs']},
      {'api': 'SYNO.Core.FileServ.AFP', 'method': 'set', 'version': 1, 'enable_afp': afp['enable_afp'], 'afp_transfer_log_enable': syslogClient['afp']},
      {'api': 'SYNO.Core.FileServ.NFS', 'method': 'set', 'version': 2, 'enable_nfs': nfs['enable_nfs'], 'enable_nfs_v4': nfs['enable_nfs_v4'], 'enable_nfs_v4_1': nfs['enable_nfs_v4'], 'nfs_v4_domain': nfs['nfs_v4_domain']},
      {'api': 'SYNO.Core.SyslogClient.FileTransfer', 'method': 'set', 'version': 1, 'cifs': syslogClient['cifs'], 'afp': syslogClient['afp']},
      {'api': 'SYNO.Core.FileServ.FTP', 'method': 'set', 'version': '3', 'enable_ftp': ftp['enable_ftp'], 'enable_ftps': ftp['enable_ftps'], 'timeout': ftp['timeout'], 'portnum': ftp['portnum'], 'custom_port_range': ftp['custom_port_range'], 'use_ext_ip': ftp['use_ext_ip'], 'enable_fxp': ftp['enable_fxp'], 'enable_fips': ftp['enable_fips'], 'enable_ascii': ftp['enable_ascii'], 'utf8_mode': ftp['utf8_mode']},
      {'api': 'SYNO.Core.FileServ.FTP.SFTP', 'method': 'set', 'version': '1', 'enable': sftp['enable'], 'sftp_portnum': sftp['portnum'], 'portnum': sftp['portnum']},
    ];
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  // -------- 媒体索引 / 桌面 / 计划任务 / 虚拟机 / Docker --------

  /// 媒体索引状态 (复合请求, DSM6 额外查询移动端配置)
  Future<Map> mediaIndexStatus() async {
    final apis = <Map>[
      {'api': 'SYNO.Core.MediaIndexing.ThumbnailQuality', 'method': 'get', 'version': 1},
      {'api': 'SYNO.Core.MediaIndexing', 'method': 'status', 'version': 1},
    ];
    if (_dsmVersion == 6) {
      apis.add({'api': 'SYNO.Core.MediaIndexing.MobileEnabled', 'method': 'get', 'version': 1});
    }
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 设置媒体索引缩略图质量 (复合请求, DSM6 额外设置移动端配置)
  Future<Map> mediaIndexSet(String thumbQuality, bool mobileEnabled) async {
    final apis = <Map>[
      {'api': 'SYNO.Core.MediaIndexing.ThumbnailQuality', 'method': 'set', 'version': '1', 'thumbnail_quality': thumbQuality},
    ];
    if (_dsmVersion == 6) {
      apis.add({'api': 'SYNO.Core.MediaIndexing.MobileEnabled', 'method': 'set', 'version': '1', 'mobile_profile_enabled': mobileEnabled});
    }
    return await post('entry.cgi', data: {
      'api': 'SYNO.Entry.Request',
      'method': 'request',
      'mode': '"sequential"',
      'compound': jsonEncode(apis),
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 重新索引媒体库
  Future<Map> mediaReindex() async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.MediaIndexing',
      'method': 'reindex',
      'version': 1,
    });
  }

  /// 桌面初始化数据
  Future<Map> initData() async {
    return await post('entry.cgi', data: {
      'launch_app': 'null',
      'api': '"SYNO.Core.Desktop.Initdata"',
      'method': '"get"',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 立即执行计划任务
  Future<Map> eventRun(String taskName) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Core.EventScheduler',
      'version': 1,
      'method': 'run',
      'task_name': taskName,
      '_sid': _sid,
    });
  }

  /// Docker 容器操作 (method 由调用方指定, 如 get/start/stop)
  Future<Map> dockerDetail(String name, String method) async {
    return await post('entry.cgi', data: {
      'api': 'SYNO.Docker.Container',
      'method': method,
      'name': '"$name"',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// 检查虚拟机是否已开机
  Future<Map> checkPowerOn(String guestId) async {
    return await post('entry.cgi', data: {
      'api': '"SYNO.Virtualization.Guest.Action"',
      'method': '"check_poweron"',
      'guest_id': '"$guestId"',
      'version': 1,
      '_sid': _sid,
    });
  }

  /// FileStation 网页版文件上传
  Future<Map> uploadWeb(String uploadPath, String filePath, CancelToken cancelToken, void Function(int, int) onSendProgress) async {
    final file = File(filePath);
    final multipartFile = MultipartFile.fromFileSync(filePath, filename: filePath.split('/').last);
    const url = 'entry.cgi?api=SYNO.FileStation.Upload&method=upload&version=2';
    final data = {
      'mtime': file.lastModifiedSync().millisecondsSinceEpoch,
      'overwrite': true,
      'path': uploadPath,
      'size': file.lengthSync(),
      'file': multipartFile,
    };
    return await upload(url, data: data, cancelToken: cancelToken, onSendProgress: onSendProgress);
  }

  // ==================== 迁移补充 API (end) ====================
}

enum FileTypeEnum {
  folder,
  image,
  movie,
  music,
  ps,
  html,
  word,
  ppt,
  excel,
  text,
  zip,
  code,
  other,
  pdf,
  apk,
  iso,
}
