import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});
  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController();
  bool _loading = true;
  bool _obscure = true;
  Map<String, dynamic> _terminalInfo = {};

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    setState(() => _loading = true);
    try {
      final res = await DsmApi().terminalInfo();
      final data = res['data'] ?? res;
      setState(() {
        _terminalInfo = data;
        _hostCtrl.text = data['host'] ?? '';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final close = AppDialog.showLoading();
    try {
      await DsmApi().setTerminal(true, false, _portCtrl.text);
      AppDialog.toast('设置已保存');
    } catch (e) {
      AppDialog.toast('保存失败: $e');
    }
    close();
  }

  void _connect() {
    if (_hostCtrl.text.isEmpty || _userCtrl.text.isEmpty) {
      AppDialog.toast('请填写完整连接信息');
      return;
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('提示'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 48.r, color: Colors.orange),
          12.hGap,
          Text('SSH 终端功能需要集成 dartssh2 包，当前为占位页面。', style: TextStyle(fontSize: 14.sp), textAlign: TextAlign.center),
          8.hGap,
          Text('连接目标：${_userCtrl.text}@${_hostCtrl.text}:${_portCtrl.text}', style: TextStyle(fontSize: 12.sp, fontFamily: 'monospace'), textAlign: TextAlign.center),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSH 终端')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('连接设置', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  12.hGap,
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.r),
                      child: Column(children: [
                        TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(labelText: '主机地址', prefixIcon: Icon(Icons.dns), border: OutlineInputBorder()),
                        ),
                        12.hGap,
                        TextField(
                          controller: _portCtrl,
                          decoration: const InputDecoration(labelText: '端口', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                        12.hGap,
                        TextField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                        ),
                        12.hGap,
                        TextField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: '密码', prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  16.hGap,
                  SizedBox(
                    width: double.infinity,
                    height: 48.h,
                    child: FilledButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.terminal),
                      label: Text('连接', style: TextStyle(fontSize: 16.sp)),
                    ),
                  ),
                  16.hGap,
                  Text('终端服务状态', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  12.hGap,
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow('SSH', _terminalInfo['enable_ssh'] == true ? '已启用' : '未启用'),
                          _infoRow('Telnet', _terminalInfo['enable_telnet'] == true ? '已启用' : '未启用'),
                          _infoRow('SSH 端口', '${_terminalInfo['ssh_port'] ?? 22}'),
                        ],
                      ),
                    ),
                  ),
                  12.hGap,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('保存终端设置'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 14.sp)),
        Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
