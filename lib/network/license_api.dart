import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/license_info.dart';
import '../models/order_info.dart';
import '../models/plan_info.dart';
import '../utils/app_preferences.dart';
import 'api_client.dart';

/// 付费权益后端接口封装（复用 [ApiClient] 的 Dio）。
///
/// 设计见 docs/付费权益系统设计方案.md §6.3。所有请求携带：
/// - `X-Trace-Id`：全链路排障（§13.1）；
/// - `X-Ts / X-Nonce / X-Sign`：轻量 HMAC 签名，防普通用户随手篡改（§9）。
class LicenseApi {
  LicenseApi._();

  factory LicenseApi() => _instance;

  static final LicenseApi _instance = LicenseApi._();

  /// 外网固定根地址（复用 zhanglei.nasfuns.fun 的 SpringBoot）。
  static const String externalRoot = 'http://zhanglei.nasfuns.fun:4001';

  /// 偏好键：内网模式开关 / 手动输入的内网根地址（调试页可切换，仿运营后台）。
  static const String prefUseInternal = 'license_use_internal';
  static const String prefInternalUrl = 'license_internal_url';

  /// 当前生效的服务器根地址（不含 /api）。内网开关开且填了地址时用内网，否则回落外网。
  static String get serverRoot {
    if (AppPreferences.getBool(prefUseInternal)) {
      final url = AppPreferences.getString(prefInternalUrl).trim();
      if (url.isNotEmpty) return url.replaceAll(RegExp(r'/+$'), '');
    }
    return externalRoot;
  }

  /// 付费权益后端基址。
  static String get baseUrl => '$serverRoot/api';

  /// 内置签名密钥（防篡改用，非绝对安全，见方案 §9）。上线前请替换。
  static const String appSecret = 'nas_license_app_secret_change_me';

  final Random _rand = Random.secure();
  final ApiClient _client = ApiClient();

  String _nonce() =>
      List.generate(12, (_) => _rand.nextInt(16).toRadixString(16)).join();

  /// 生成一次请求的 traceId，供 App 本地日志与后端串联。
  String newTraceId() =>
      '${DateTime.now().millisecondsSinceEpoch}-${_nonce()}';

  Options _signedOptions(String body, String traceId) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final sign = Hmac(sha256, utf8.encode(appSecret))
        .convert(utf8.encode('$body$ts$nonce'))
        .toString();
    return Options(headers: {
      'X-Trace-Id': traceId,
      'X-Ts': ts,
      'X-Nonce': nonce,
      'X-Sign': sign,
    });
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
    String? traceId,
  }) async {
    final tid = traceId ?? newTraceId();
    final data = await _client.request<dynamic>(
      '$baseUrl$path',
      method: 'GET',
      queryParameters: query,
      options: _signedOptions('', tid),
      showErrorToast: false,
    );
    return _asMap(data);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic> body = const {},
    String? traceId,
  }) async {
    final tid = traceId ?? newTraceId();
    final encoded = jsonEncode(body);
    final data = await _client.request<dynamic>(
      '$baseUrl$path',
      method: 'POST',
      data: body,
      options: _signedOptions(encoded, tid),
      showErrorToast: false,
    );
    return _asMap(data);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  // ==================== 设备识别 ====================

  /// 管理员上报硬件特征，返回 deviceId + 当前权益快照。
  Future<LicenseInfo> registerDevice({
    required String serial,
    required String model,
    required String mac,
    required String hostname,
    required String domain,
    String? traceId,
  }) async {
    final data = await _post('/device/register', body: {
      'serial': serial,
      'model': model,
      'mac': mac,
      'hostname': hostname,
      'domain': domain,
    }, traceId: traceId);
    return LicenseInfo.fromJson(data);
  }

  /// 普通用户按域名查询设备与权益（未命中返回 UNKNOWN）。
  Future<LicenseInfo> queryByDomain(String domain, {String? traceId}) async {
    final data = await _get('/device/queryByDomain',
        query: {'domain': domain}, traceId: traceId);
    return LicenseInfo.fromJson(data);
  }

  /// 查询当前权益状态。
  Future<LicenseInfo> licenseStatus(String deviceId, {String? traceId}) async {
    final data = await _get('/license/status',
        query: {'deviceId': deviceId}, traceId: traceId);
    return LicenseInfo.fromJson(data);
  }

  // ==================== 试用 ====================

  /// 申请免费试用（每台设备一次）。
  Future<LicenseInfo> applyTrial(String deviceId, {String? traceId}) async {
    final data = await _post('/trial/apply',
        body: {'deviceId': deviceId}, traceId: traceId);
    return LicenseInfo.fromJson(data);
  }

  // ==================== 套餐 / 订单 ====================

  /// 拉取套餐列表（后台可配）。
  Future<List<PlanInfo>> fetchPlans({String? traceId}) async {
    final data = await _get('/config/plans', traceId: traceId);
    final list = (data['plans'] ?? data['list'] ?? data['data'] ?? []) as List?;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((e) => PlanInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 创建订单，返回 orderId + 收款二维码。payRemark 为用户选填的付款备注（空则不传）。
  Future<OrderInfo> createOrder({
    required String deviceId,
    required String plan,
    String? payRemark,
    String? traceId,
  }) async {
    final body = <String, dynamic>{'deviceId': deviceId, 'plan': plan};
    if (payRemark != null && payRemark.trim().isNotEmpty) {
      body['payRemark'] = payRemark.trim();
    }
    final data = await _post('/order/create', body: body, traceId: traceId);
    return OrderInfo.fromJson(data);
  }

  /// 用户点「我已付款」，订单转 USER_PAID → WAIT_CONFIRM。
  /// suspicious=true 表示用户未离开 App 即点（疑似未真实付款），后台标记存疑。
  /// payProofUrl 为付款凭证截图的服务端 URL。
  Future<OrderInfo> paidCheck(String orderId,
      {bool suspicious = false, String? payProofUrl, String? traceId}) async {
    final body = <String, dynamic>{'orderId': orderId, 'suspicious': suspicious};
    if (payProofUrl != null && payProofUrl.isNotEmpty) {
      body['payProofUrl'] = payProofUrl;
    }
    final data = await _post('/order/paid-check', body: body, traceId: traceId);
    // 后端可能只回 status，这里补齐 orderId 方便展示。
    if (data['orderId'] == null) data['orderId'] = orderId;
    return OrderInfo.fromJson(data);
  }

  /// 轮询订单状态。
  Future<OrderInfo> orderStatus(String orderId, {String? traceId}) async {
    final data =
        await _get('/order/status', query: {'orderId': orderId}, traceId: traceId);
    if (data['orderId'] == null) data['orderId'] = orderId;
    return OrderInfo.fromJson(data);
  }

  /// 拉取本设备历史订单 + 当前权益是否被管理员禁用及原因。
  ///
  /// 返回后端 data：{orders:[...], revoked:bool, revokeReason, revokeTime}。
  Future<Map<String, dynamic>> fetchOrders(String deviceId, {String? traceId}) async {
    return _get('/order/list', query: {'deviceId': deviceId}, traceId: traceId);
  }

  // ==================== 文件上传 ====================

  /// 上传图片文件，返回服务端可访问的 URL 路径（如 /uploads/xxx.jpg）。
  Future<String> uploadImage(String filePath, {String? traceId}) async {
    final tid = traceId ?? newTraceId();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await _client.request<dynamic>(
      '$baseUrl/upload',
      method: 'POST',
      data: formData,
      options: Options(headers: {'X-Trace-Id': tid}),
      showErrorToast: false,
    );
    final map = _asMap(resp);
    final url = (map['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('上传失败：服务端未返回 URL');
    return url;
  }

  // ==================== 解封申诉 ====================

  /// 被封禁设备提交解封申诉。返回 {appealStatus, canSubmit, reason, adminRemark, ...}。
  Future<Map<String, dynamic>> submitAppeal(String deviceId, String reason,
      {String? traceId}) async {
    return _post('/appeal/submit',
        body: {'deviceId': deviceId, 'reason': reason}, traceId: traceId);
  }

  /// 查询本设备申诉状态（含是否可再次提交 canSubmit）。
  Future<Map<String, dynamic>> appealStatus(String deviceId,
      {String? traceId}) async {
    return _get('/appeal/status', query: {'deviceId': deviceId}, traceId: traceId);
  }

  // ==================== 意见反馈 ====================

  /// 偏好键：反馈归属的本地安装标识（首次生成后固定，重装 App 会变）。
  static const String prefClientId = 'feedback_client_id';

  /// 本安装的反馈客户端标识：首次调用生成（时间戳+安全随机数），持久化后不变。
  static String get clientId {
    var id = AppPreferences.getString(prefClientId);
    if (id.isEmpty) {
      final rand = Random.secure();
      final suffix =
          List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
      id = 'fc-${DateTime.now().millisecondsSinceEpoch}-$suffix';
      AppPreferences.putString(prefClientId, id);
    }
    return id;
  }

  /// 提交意见反馈（文字 ≤300 字 + 图片 URL ≤9 张 + 硬件信息快照）。
  Future<Map<String, dynamic>> submitFeedback({
    required String content,
    List<String> images = const [],
    Map<String, Object?> hardware = const {},
    String? deviceId,
    String? traceId,
  }) async {
    return _post('/feedback/submit', body: {
      'clientId': clientId,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      'content': content,
      'images': images,
      'hardware': hardware,
    }, traceId: traceId);
  }

  /// 我的反馈列表（按本机 clientId，倒序，含 status/adminReply）。
  Future<List<Map<String, dynamic>>> feedbackList({String? traceId}) async {
    final tid = traceId ?? newTraceId();
    final data = await _client.request<dynamic>(
      '$baseUrl/feedback/list',
      method: 'GET',
      queryParameters: {'clientId': clientId},
      options: _signedOptions('', tid),
      showErrorToast: false,
    );
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// 开发计划与公告（markdown 文本 + 更新时间，后台配置）。
  Future<Map<String, dynamic>> fetchAnnouncement({String? traceId}) {
    return _get('/config/announcement', traceId: traceId);
  }
}
