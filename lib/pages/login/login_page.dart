import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_logger.dart';
import '../../utils/app_preferences.dart';
import '../../utils/license_manager.dart';
import '../../models/server_model.dart';
import '../license/banned_page.dart';
import '../license/paywall_page.dart';
import 'accounts_page.dart';

class LoginPage extends StatefulWidget {
  final ServerModel? server;
  final String type; // "login" or "add"
  const LoginPage({super.key, this.server, this.type = 'login'});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _hostController = TextEditingController();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController();
  final _otpController = TextEditingController();
  final _noteController = TextEditingController();
  final _cancelToken = CancelToken();

  String _host = '';
  String _account = '';
  String _password = '';
  String _port = '5000';
  String _note = '';
  String _otpToken = '';
  bool _https = false;
  bool _isLoading = false;
  bool _rememberPassword = true;
  bool _autoLogin = true;
  bool _checkSsl = true;
  bool _rememberDevice = false;
  List<ServerModel> _servers = [];

  @override
  void initState() {
    super.initState();
    _loadSavedInfo();
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    _hostController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _otpController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedInfo() async {
    final serversStr = AppPreferences.getString('servers');
    _servers = ServerModel.listFromStorage(serversStr);

    if (widget.server != null) {
      final s = widget.server!;
      setState(() {
        _https = s.https;
        _host = s.host;
        _port = s.port;
        _account = s.account;
        _note = s.note;
        _password = s.password;
        _autoLogin = s.autoLogin;
        _rememberPassword = s.rememberPassword;
        _checkSsl = s.checkSsl;
        _hostController.text = s.host;
        _portController.text = s.port;
        _accountController.text = s.account;
        _noteController.text = s.note;
        _passwordController.text = s.password;
      });
      DsmApi().setServer(s);
      if (widget.type == 'login') _doLogin();
    } else if (widget.type == 'login') {
      _restoreLastSession();
    } else {
      _portController.text = _port;
    }
  }

  Future<void> _restoreLastSession() async {
    final host = AppPreferences.getString('host');
    final baseUrl = AppPreferences.getString('base_url');
    final account = AppPreferences.getString('account');
    final password = AppPreferences.getString('password');
    final sid = AppPreferences.getString('sid');
    final smid = AppPreferences.getString('smid');
    final httpsStr = AppPreferences.getString('https');
    final portStr = AppPreferences.getString('port');
    final note = AppPreferences.getString('note');
    final checkSslStr = AppPreferences.getString('check_ssl');
    final autoLoginStr = AppPreferences.getString('auto_login');

    if (httpsStr.isNotEmpty) _https = httpsStr == '1';
    if (checkSslStr.isNotEmpty) _checkSsl = checkSslStr == '1';
    if (autoLoginStr.isNotEmpty) _autoLogin = autoLoginStr == '1';

    final rememberPasswordStr = AppPreferences.getString('remember_password');
    if (rememberPasswordStr.isNotEmpty) _rememberPassword = rememberPasswordStr == '1';

    setState(() {
      _host = host;
      _account = account;
      _note = note;
      _password = password;
      if (host.isNotEmpty) _hostController.text = host;
      if (portStr.isNotEmpty) {
        _port = portStr;
        _portController.text = portStr;
      } else {
        _portController.text = _port;
      }
      if (account.isNotEmpty) _accountController.text = account;
      if (note.isNotEmpty) _noteController.text = note;
      if (password.isNotEmpty) _passwordController.text = password;
    });

    if (sid.isNotEmpty && host.isNotEmpty && _autoLogin) {
      final server = ServerModel(
        host: host,
        port: _port,
        https: _https,
        account: account,
        password: password,
        note: note,
        baseUrl: baseUrl,
        checkSsl: _checkSsl,
        sid: sid,
        cookie: smid,
      );
      DsmApi().setServer(server);
      DsmApi().setSession(sid: sid, cookie: smid);
      setState(() => _isLoading = true);

      final check = await DsmApi().shareList(cancelToken: _cancelToken);
      setState(() => _isLoading = false);
      if (check['success'] != false && check['data'] != null) {
        // 自动登录（会话恢复）同样要经过权益门禁：无有效权益的已识别设备
        // 会被导向 PaywallPage 引导领取免费周卡/购买，而不是直接进首页。
        await _checkLicenseAndEnter();
        return;
      }
      _doLogin();
    }
  }

  Future<void> _doLogin() async {
    if (_host.trim().isEmpty) {
      AppDialog.toast('请输入网址/IP/QuickConnect ID');
      return;
    }
    if (_account.isEmpty) {
      AppDialog.toast('请输入账号');
      return;
    }

    setState(() => _isLoading = true);

    if (_host.contains('.') || _host.contains(':')) {
      final baseUri =
          '${_https ? "https" : "http"}://${_host.trim()}:${_port.trim()}';
      await _performLogin(baseUri);
    } else {
      await _quickConnectLogin();
    }
  }

  Future<void> _quickConnectLogin({String qcHost = 'global.quickconnect.cn'}) async {
    final qcAddresses = <String>[];
    final res = await DsmApi().quickConnect(_host, baseUrl: qcHost);

    if (res['errno'] == 0) {
      if (res['server']['fqdn'] != 'NULL') {
        qcAddresses.add('http://${res['server']['fqdn']}/');
      }
      if (res['server']['external']?['ip'] != null) {
        qcAddresses.add(
            'http://${res['server']['external']['ip']}:${res['service']['ext_port']}/');
      }
      if (res['service']['relay_ip'] != null) {
        qcAddresses.add(
            'http://${res['service']['relay_ip']}:${res['service']['relay_port']}/');
      }
      if (res['server']['ddns'] != 'NULL') {
        qcAddresses.add(
            'http://${res['server']['ddns']}:${res['service']['ext_port']}/');
      }
      if (res['server']['interface'] != null) {
        for (final interface in res['server']['interface']) {
          qcAddresses
              .add('http://${interface['ip']}:${res['service']['port']}/');
          if (interface['ipv6'] != null) {
            for (final v6 in interface['ipv6']) {
              qcAddresses
                  .add('http://[${v6['address']}]:${res['service']['port']}/');
            }
          }
        }
      }
      if (res['service']['relay_ip'] == null) {
        final cnRes = await DsmApi()
            .quickConnectCn(_host, baseUrl: res['env']['control_host']);
        if (cnRes['errno'] == 0 && cnRes['service']['relay_ip'] != null) {
          qcAddresses.add(
              'http://${cnRes['service']['relay_ip']}:${cnRes['service']['relay_port']}/');
        }
      }

      bool found = false;
      final completer = Completer<void>();
      int pending = qcAddresses.length;

      for (final address in qcAddresses) {
        DsmApi().pingpong(address).then((result) {
          if (result != null && !found) {
            found = true;
            _performLogin(result);
          }
          pending--;
          if (pending <= 0 && !completer.isCompleted) {
            completer.complete();
          }
        });
      }

      await completer.future;
      if (!found) {
        setState(() => _isLoading = false);
        AppDialog.toast('无法连接到服务器');
      }
    } else if (res['errno'] == 4 &&
        res['errinfo']?.toString().startsWith('get_server_info.go') == true &&
        res['sites'] != null &&
        (res['sites'] as List).isNotEmpty) {
      _quickConnectLogin(qcHost: res['sites'][0]);
    } else {
      setState(() => _isLoading = false);
      AppDialog.toast('无法连接到服务器，请检查QuickConnect ID是否正确');
    }
  }

  Future<void> _performLogin(String baseUri, {String otpCode = '', String? otpToken}) async {
    final dsmApi = DsmApi();
    final tempServer = ServerModel(
      host: _host,
      port: _port,
      https: _https,
      account: _account,
      password: _password,
      baseUrl: baseUri,
      checkSsl: _checkSsl,
    );
    dsmApi.setServer(tempServer);

    final res = await dsmApi.login(
      host: baseUri,
      account: _account,
      password: _password,
      otpCode: otpCode,
      otpToken: otpToken,
      cancelToken: _cancelToken,
      rememberDevice: _rememberDevice,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      final sid = res['data']['sid'];
      dsmApi.setSession(sid: sid, cookie: dsmApi.cookie);
      // 提取 SynoToken 用于 WebView 自动登录
      debugPrint('【调试】登录响应 data: ${res['data']}');
      final synoToken = res['data']['synotoken'] ?? res['data']['SynoToken'] ?? '';
      debugPrint('【调试】提取到的 synoToken: "$synoToken"');
      if (synoToken is String && synoToken.isNotEmpty) {
        dsmApi.setSynoToken(synoToken);
      }
      _saveLoginInfo(baseUri, sid);
      _saveServerRecord(baseUri, sid);

      if (widget.type == 'login') {
        await _checkLicenseAndEnter();
      } else {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() => _isLoading = false);
      final code = res['error']?['code'];
      if (code == 400) {
        AppDialog.toast('用户名/密码有误');
      } else if (code == 403) {
        // 需要 OTP —— 弹窗输入
        // 提取 OTP token（JWT）用于第二次带 OTP 的登录请求（version 6+ 必需）
        _otpToken = res['error']?['errors']?['token'] ?? '';
        _showOtpDialog(baseUri);
      } else if (code == 404) {
        _otpController.clear();
        AppDialog.toast('错误的验证代码，请重试');
        _otpToken = res['error']?['errors']?['token'] ?? '';
        _showOtpDialog(baseUri);
      } else {
        AppDialog.toast('登录失败，code: $code');
      }
    }
  }

  /// 登录成功后检测付费权益：
  /// - 有效权益或未识别设备（弱识别/黑群晖）：正常进入首页；
  /// - 已识别但无有效权益：跳转付费引导页；
  /// - 权益接口异常：走宽限逻辑，绝不因网络问题阻断登录，默认进入首页。
  Future<void> _checkLicenseAndEnter() async {
    AppLogger.section('登录后权益校验');
    String target = '/';
    try {
      final info = await LicenseManager().refresh(force: true);
      AppLogger.d('Login', '权益结果: status=${info.status}, banned=${info.isBanned}, '
          'shouldBlock=${info.shouldBlock}, deviceId=${info.deviceId}');
      if (info.isBanned) {
        target = BannedPage.routeName;
        AppLogger.w('Login', '设备已封禁→跳转BannedPage');
      } else if (info.shouldBlock) {
        target = PaywallPage.routeName;
        AppLogger.w('Login', '无有效权益→跳转PaywallPage');
      } else {
        AppLogger.d('Login', '权益正常→进入主页');
      }
    } catch (e) {
      AppLogger.e('Login', '权益检测异常(放行): $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
  }

  /// OTP 二次验证弹窗
  void _showOtpDialog(String baseUri) {
    _otpController.clear();
    _rememberDevice = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 12),
                      const Text(
                        '二步验证',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请输入验证器应用中显示的 6 位验证码',
                    style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _otpController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 12,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '000000',
                      hintStyle: TextStyle(
                        color: Theme.of(ctx).hintColor.withOpacity(0.3),
                        letterSpacing: 12,
                      ),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _submitOtp(ctx, baseUri),
                  ),
                  const SizedBox(height: 16),
                  // 记住设备
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setSheetState(() => _rememberDevice = !_rememberDevice);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _rememberDevice
                            ? Theme.of(ctx).colorScheme.primaryContainer.withOpacity(0.3)
                            : Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _rememberDevice
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: _rememberDevice
                                ? Theme.of(ctx).colorScheme.primary
                                : Theme.of(ctx).hintColor,
                          ),
                          const SizedBox(width: 12),
                          const Text('记住此设备'),
                          const Spacer(),
                          Text(
                            '下次登录无需验证码',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => _submitOtp(ctx, baseUri),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('验证', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _submitOtp(BuildContext ctx, String baseUri) {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      AppDialog.toast('请输入验证码');
      return;
    }
    Navigator.pop(ctx);
    setState(() => _isLoading = true);
    _performLogin(baseUri, otpCode: otp, otpToken: _otpToken);
  }

  void _saveLoginInfo(String baseUri, String sid) {
    AppPreferences.putString('https', _https ? '1' : '0');
    AppPreferences.putString('host', _host.trim());
    AppPreferences.putString('port', _port);
    AppPreferences.putString('base_url', baseUri);
    AppPreferences.putString('account', _account);
    AppPreferences.putString('note', _note);
    AppPreferences.putString('remember_password', _rememberPassword ? '1' : '0');
    AppPreferences.putString('auto_login', _autoLogin ? '1' : '0');
    AppPreferences.putString('check_ssl', _checkSsl ? '1' : '0');
    AppPreferences.putString('sid', sid);
    if (_rememberPassword) {
      AppPreferences.putString('password', _password);
    } else {
      AppPreferences.remove('password');
    }
  }

  void _saveServerRecord(String baseUri, String sid) {
    bool exist = false;
    for (int i = 0; i < _servers.length; i++) {
      final s = _servers[i];
      if (s.https == _https &&
          s.host == _host &&
          s.port == _port &&
          s.account == _account) {
        _servers[i] = s.copyWith(
          password: _rememberPassword ? _password : '',
          note: _note,
          rememberPassword: _rememberPassword,
          autoLogin: _autoLogin,
          checkSsl: _checkSsl,
          cookie: DsmApi().cookie,
          sid: sid,
          baseUrl: baseUri,
        );
        exist = true;
        break;
      }
    }
    if (!exist) {
      _servers.add(ServerModel(
        https: _https,
        host: _host,
        port: _port,
        note: _note,
        account: _account,
        password: _rememberPassword ? _password : '',
        rememberPassword: _rememberPassword,
        autoLogin: _autoLogin,
        checkSsl: _checkSsl,
        cookie: DsmApi().cookie,
        sid: sid,
        baseUrl: baseUri,
      ));
    }
    AppPreferences.putString('servers', ServerModel.listToJson(_servers));
  }

  /// 实时保存用户输入的登录信息（无需登录成功）
  void _saveCurrentInputs() {
    AppPreferences.putString('host', _host.trim());
    AppPreferences.putString('port', _port);
    AppPreferences.putString('account', _account);
    AppPreferences.putString('note', _note);
    AppPreferences.putString('https', _https ? '1' : '0');
    AppPreferences.putString('check_ssl', _checkSsl ? '1' : '0');
    AppPreferences.putString('auto_login', _autoLogin ? '1' : '0');
    AppPreferences.putString('remember_password', _rememberPassword ? '1' : '0');
    if (_rememberPassword) {
      AppPreferences.putString('password', _password);
    }
  }

  void _toggleHttps() {
    setState(() {
      _https = !_https;
      if (_https && _port == '5000') {
        _port = '5001';
        _portController.text = _port;
      } else if (!_https && _port == '5001') {
        _port = '5000';
        _portController.text = _port;
      }
      _saveCurrentInputs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type == 'login' ? '账号登录' : '添加账号'),
        actions: [
          if (_servers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '历史账号',
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountsPage(servers: _servers),
                  ),
                );
                if (result == true && mounted) {
                  _loadSavedInfo();
                }
              },
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),

            // 服务器地址
            _buildServerAddressField(theme),
            const SizedBox(height: 16),

            // 账号 + 备注
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _accountController,
                    label: '账号',
                    onChanged: (v) { _account = v; _saveCurrentInputs(); },
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _noteController,
                    label: '备注',
                    onChanged: (v) { _note = v; _saveCurrentInputs(); },
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 密码
            _buildTextField(
              controller: _passwordController,
              label: '密码',
              obscureText: true,
              onChanged: (v) { _password = v; _saveCurrentInputs(); },
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),

            // 选项
            Row(
              children: [
                Expanded(
                  child: _buildToggleCard(
                    label: '记住密码',
                    value: _rememberPassword,
                    onTap: () => setState(() {
                      _rememberPassword = !_rememberPassword;
                      if (!_rememberPassword) _autoLogin = false;
                      _saveCurrentInputs();
                    }),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildToggleCard(
                    label: '自动登录',
                    value: _autoLogin,
                    onTap: () => setState(() {
                      _autoLogin = !_autoLogin;
                      if (_autoLogin) _rememberPassword = true;
                      _saveCurrentInputs();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // SSL 选项
            if (_https) ...[
              _buildToggleCard(
                label: '验证SSL证书',
                value: _checkSsl,
                onTap: () => setState(() { _checkSsl = !_checkSsl; _saveCurrentInputs(); }),
                fullWidth: true,
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 16),

            // 登录按钮
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isLoading ? null : _doLogin,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('登录', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerAddressField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleHttps,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('协议',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
                Text(
                  _https ? 'https' : 'http',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _hostController,
              autocorrect: false,
              onChanged: (v) => setState(() { _host = v; _saveCurrentInputs(); }),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: InputBorder.none,
                labelText: '网址/IP/QuickConnect ID',
              ),
            ),
          ),
          if (_host.contains('.') || _host.contains(':'))
            SizedBox(
              width: 80,
              child: TextField(
                controller: _portController,
                onChanged: (v) { _port = v; _saveCurrentInputs(); },
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  labelText: '端口',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        autocorrect: false,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required String label,
    required bool value,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: fullWidth ? 52 : 60,
        decoration: BoxDecoration(
          color: value
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: value
              ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3))
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(label),
            const Spacer(),
            if (value)
              Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
