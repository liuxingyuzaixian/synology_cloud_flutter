import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../mine/dashboard_page.dart';

/// 个人设置页面
/// 可查看/修改当前登录用户的描述、邮箱、密码、两步验证等
class PersonalSettingsPage extends StatefulWidget {
  const PersonalSettingsPage({super.key});

  @override
  State<PersonalSettingsPage> createState() => _PersonalSettingsPageState();
}

class _PersonalSettingsPageState extends State<PersonalSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _userData;

  final _fullnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _oldPwdController = TextEditingController();
  final _newPwdController = TextEditingController();
  final _confirmPwdController = TextEditingController();

  /// 记录用户修改的字段
  final Map<String, dynamic> _changedData = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullnameController.dispose();
    _emailController.dispose();
    _oldPwdController.dispose();
    _newPwdController.dispose();
    _confirmPwdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DsmApi().normalUser('get');
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null) {
        _userData = data;
        _fullnameController.text = data['fullname']?.toString() ?? '';
        _emailController.text = data['email']?.toString() ?? '';
      }
    } catch (e) {
      AppDialog.toast('加载失败');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final data = <String, dynamic>{};

    // 描述
    if (_fullnameController.text != (_userData?['fullname'] ?? '')) {
      data['fullname'] = _fullnameController.text;
    }
    // 邮箱
    if (_emailController.text != (_userData?['email'] ?? '')) {
      data['email'] = _emailController.text;
    }
    // 密码修改
    if (_oldPwdController.text.isNotEmpty) {
      if (_newPwdController.text.isEmpty) {
        AppDialog.toast('请输入新密码');
        return;
      }
      if (_newPwdController.text != _confirmPwdController.text) {
        AppDialog.toast('确认密码与新密码不一致');
        return;
      }
      data['old_password'] = _oldPwdController.text;
      data['password'] = _newPwdController.text;
    }

    // OTP 关闭
    _changedData.forEach((k, v) {
      if (v is bool) data[k] = v;
    });

    if (data.isEmpty) {
      AppDialog.toast('无修改内容');
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await DsmApi().normalUser('set', changedData: data);
      if (res['success'] == true) {
        AppDialog.toast('保存成功');
        _oldPwdController.clear();
        _newPwdController.clear();
        _confirmPwdController.clear();
        _changedData.clear();
        await _load();
      } else {
        final errCode = res['error']?['code'];
        AppDialog.toast('保存失败${errCode != null ? '，错误码: $errCode' : ''}');
      }
    } catch (e) {
      AppDialog.toast('保存失败');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: '仪表盘',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardPage())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? Center(child: Text('加载失败', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
              : SingleChildScrollView(
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户信息卡片
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.aw),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28.aw,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Icon(Icons.person, size: 32.aw, color: theme.colorScheme.onPrimaryContainer),
                              ),
                              SizedBox(width: 16.aw),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _userData!['username']?.toString() ?? '未知用户',
                                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(height: 4.h),
                                    if (_userData!['OTP_enable'] == true)
                                      Row(
                                        children: [
                                          Icon(Icons.verified_user, size: 14.r, color: Colors.orange),
                                          SizedBox(width: 4.w),
                                          Text('两步验证已开启', style: TextStyle(fontSize: 12.sp, color: Colors.orange)),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // 基本信息编辑
                      _buildSectionTitle('基本信息'),
                      _buildCard([
                        _buildTextField(
                          controller: TextEditingController(text: _userData!['username']?.toString() ?? ''),
                          label: '用户名',
                          enabled: false,
                        ),
                        _divider(),
                        _buildTextField(
                          controller: _fullnameController,
                          label: '描述',
                          onChanged: (v) => _changedData['fullname'] = v,
                        ),
                        _divider(),
                        _buildTextField(
                          controller: _emailController,
                          label: '邮箱',
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (v) => _changedData['email'] = v,
                        ),
                      ]),
                      SizedBox(height: 16.h),

                      // 密码修改
                      if (_userData!['disallowchpasswd'] != true) ...[
                        _buildSectionTitle('修改密码'),
                        _buildCard([
                          _buildTextField(
                            controller: _oldPwdController,
                            label: '当前密码',
                            obscure: true,
                          ),
                          _divider(),
                          _buildTextField(
                            controller: _newPwdController,
                            label: '新密码',
                            obscure: true,
                          ),
                          _divider(),
                          _buildTextField(
                            controller: _confirmPwdController,
                            label: '确认新密码',
                            obscure: true,
                          ),
                        ]),
                        SizedBox(height: 16.h),
                      ],

                      // 两步验证
                      _buildSectionTitle('安全设置'),
                      _buildCard([
                        SwitchListTile(
                          title: const Text('两步验证'),
                          subtitle: Text(
                            _userData!['OTP_enable'] == true ? '已开启' : '未开启',
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                          ),
                          value: _userData!['OTP_enable'] == true,
                          onChanged: (v) {
                            if (v) {
                              AppDialog.toast('两步验证绑定功能开发中');
                            } else {
                              setState(() {
                                _userData!['OTP_enable'] = false;
                                _changedData['disableOTP'] = true;
                              });
                            }
                          },
                        ),
                      ]),
                      SizedBox(height: 24.h),

                      // 保存按钮
                      SizedBox(
                        width: double.infinity,
                        height: 48.h,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('保存'),
                        ),
                      ),
                      SizedBox(height: 32.h),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(left: 4.aw, bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Theme.of(context).hintColor),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, indent: 16.w, endIndent: 16.w);

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}
