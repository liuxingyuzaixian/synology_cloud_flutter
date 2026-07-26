import 'dart:convert';

/// 群晖服务器连接信息
class ServerModel {
  final String host;
  final String port;
  final bool https;
  final String account;
  final String password;
  final String note;
  final String baseUrl;
  final bool rememberPassword;
  final bool autoLogin;
  final bool checkSsl;
  final String? sid;
  final String? cookie;
  final int dsmVersion; // 6 or 7

  const ServerModel({
    required this.host,
    this.port = '5000',
    this.https = false,
    required this.account,
    this.password = '',
    this.note = '',
    this.baseUrl = '',
    this.rememberPassword = true,
    this.autoLogin = true,
    this.checkSsl = true,
    this.sid,
    this.cookie,
    this.dsmVersion = 7,
  });

  String get fullUrl {
    if (baseUrl.isNotEmpty) return baseUrl;
    return '${https ? "https" : "http"}://$host:$port';
  }

  bool get isQuickConnect => !host.contains('.') && !host.contains(':');

  ServerModel copyWith({
    String? host,
    String? port,
    bool? https,
    String? account,
    String? password,
    String? note,
    String? baseUrl,
    bool? rememberPassword,
    bool? autoLogin,
    bool? checkSsl,
    String? sid,
    String? cookie,
    int? dsmVersion,
  }) {
    return ServerModel(
      host: host ?? this.host,
      port: port ?? this.port,
      https: https ?? this.https,
      account: account ?? this.account,
      password: password ?? this.password,
      note: note ?? this.note,
      baseUrl: baseUrl ?? this.baseUrl,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      autoLogin: autoLogin ?? this.autoLogin,
      checkSsl: checkSsl ?? this.checkSsl,
      sid: sid ?? this.sid,
      cookie: cookie ?? this.cookie,
      dsmVersion: dsmVersion ?? this.dsmVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'https': https,
        'account': account,
        'password': password,
        'note': note,
        'base_url': baseUrl,
        'remember_password': rememberPassword,
        'auto_login': autoLogin,
        'check_ssl': checkSsl,
        'sid': sid,
        'cookie': cookie,
        'dsm_version': dsmVersion,
      };

  factory ServerModel.fromJson(Map<String, dynamic> json) => ServerModel(
        host: json['host'] ?? '',
        port: json['port'] ?? '5000',
        https: json['https'] ?? false,
        account: json['account'] ?? '',
        password: json['password'] ?? '',
        note: json['note'] ?? '',
        baseUrl: json['base_url'] ?? '',
        rememberPassword: json['remember_password'] ?? true,
        autoLogin: json['auto_login'] ?? true,
        checkSsl: json['check_ssl'] ?? true,
        sid: json['sid'],
        cookie: json['cookie'],
        dsmVersion: json['dsm_version'] ?? 7,
      );

  static List<ServerModel> listFromStorage(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List;
      return list.map((e) => ServerModel.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<ServerModel> servers) {
    return jsonEncode(servers.map((e) => e.toJson()).toList());
  }
}
