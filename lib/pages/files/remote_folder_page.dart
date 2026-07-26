import 'dart:async';
import 'package:flutter/material.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';

//装载远程文件夹
class RemoteFolderPage extends StatefulWidget {
  const RemoteFolderPage();
  @override
  State<RemoteFolderPage> createState() => RemoteFolderPageState();
}

class RemoteFolderPageState extends State<RemoteFolderPage> {
  final _hostController = TextEditingController();
  final _mountPointController = TextEditingController(text: '/');
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _autoMount = false;
  int _type = 0; // 0=CIFS, 1=FTP
  bool _loading = false;

  @override
  void dispose() {
    _hostController.dispose();
    _mountPointController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _mount() async {
    if (_hostController.text.trim().isEmpty) {
      AppDialog.toast('请输入服务器地址');
      return;
    }
    setState(() => _loading = true);
    // Mount via DSM API
    try {
      final res = await DsmApi().post('entry.cgi', data: {
        'api': 'SYNO.Core.RemoteFolder',
        'method': 'mount',
        'version': 1,
        'type': _type == 0 ? 'cifs' : 'ftp',
        'host': _hostController.text.trim(),
        'mount_point': _mountPointController.text.trim(),
        'account': _accountController.text.trim(),
        'password': _passwordController.text.trim(),
        'auto_mount': _autoMount,
      });
      setState(() => _loading = false);
      if (res['success'] == true) {
        AppDialog.toast('装载成功');
        Navigator.pop(context);
      } else {
        AppDialog.toast('装载失败: ${res['error']?['code'] ?? ''}');
      }
    } catch (e) {
      setState(() => _loading = false);
      AppDialog.toast('装载失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('装载远程文件夹')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('CIFS')),
              ButtonSegment(value: 1, label: Text('FTP')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          SizedBox(height: 16),
          TextField(controller: _hostController, decoration: const InputDecoration(labelText: '服务器地址', hintText: '192.168.1.100', border: OutlineInputBorder())),
          SizedBox(height: 12),
          TextField(controller: _mountPointController, decoration: const InputDecoration(labelText: '挂载点', hintText: '/remote', border: OutlineInputBorder())),
          SizedBox(height: 12),
          TextField(controller: _accountController, decoration: const InputDecoration(labelText: '账号（可选）', border: OutlineInputBorder())),
          SizedBox(height: 12),
          TextField(controller: _passwordController, decoration: const InputDecoration(labelText: '密码（可选）', border: OutlineInputBorder()), obscureText: true),
          SizedBox(height: 12),
          SwitchListTile(title: const Text('开机自动挂载'), value: _autoMount, onChanged: (v) => setState(() => _autoMount = v)),
          SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _mount,
            icon: _loading ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
            label: Text(_loading ? '装载中...' : '装载'),
          ),
        ],
      ),
    );
  }
}
