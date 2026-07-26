import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app.dart';
import '../../components/app_dialog.dart';
import '../../components/debug_tools.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_preferences.dart';
import '../../utils/cache_manager_util.dart';
import '../../utils/fly_router.dart';
import '../../models/server_model.dart';
import '../../models/webview_entry.dart';
import 'about_page.dart';
import 'dashboard_page.dart';
import 'personal_settings_page.dart';
import '../license/license_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  List<WebViewEntry> _webViewEntries = [];
  int _titleTapCount = 0;
  DateTime? _titleFirstTap;
  String _appVersion = '...';
  int? _cacheSize; // null 表示计算中

  @override
  void initState() {
    super.initState();
    _darkMode = AppPreferences.getBool('darkMode');
    _loadWebViewEntries();
    _loadVersion();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    try {
      final size = await CacheManagerUtil.totalCacheSize();
      if (mounted) setState(() => _cacheSize = size);
    } catch (_) {
      if (mounted) setState(() => _cacheSize = 0);
    }
  }

  Future<void> _clearCache() async {
    final sizeText = _cacheSize == null ? '' : '，将释放 ${DsmApi.formatSize(_cacheSize!)}B 空间';
    final confirm = await AppDialog.confirm(
      title: '清理缓存',
      message: '将清理图片和视频缓存$sizeText，是否继续？',
      confirmText: '清理',
    );
    if (!confirm) return;

    final close = AppDialog.showLoading(label: '清理中...');
    try {
      await CacheManagerUtil.clearCache();
      close();
      AppDialog.toast('清理完成');
    } catch (e) {
      close();
      AppDialog.toast('清理失败: $e');
    }
    setState(() => _cacheSize = null);
    _loadCacheSize();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final versionStr = info.version; // e.g. "0.0.2"
      final buildNum = int.tryParse(info.buildNumber) ?? 0;
      if (mounted) setState(() => _appVersion = buildNum > 0 ? '$versionStr+$buildNum' : versionStr);
    } catch (_) {
      if (mounted) setState(() => _appVersion = '0.0.2'); // fallback
    }
  }

  void _loadWebViewEntries() {
    final json = AppPreferences.getString('webview_entries');
    var entries = WebViewEntry.listFromStorage(json);
    setState(() {
      _webViewEntries = entries;
    });
  }

  void _toggleDarkMode(bool value) {
    setState(() => _darkMode = value);
    AppPreferences.putBool('darkMode', value);
    darkModeNotifier.value = value;
  }

  Future<void> _logout() async {
    final confirm = await AppDialog.confirm(
      title: '退出登录',
      message: '确定要退出当前账号吗？',
    );
    if (confirm != true) return;

    final loading = AppDialog.showLoading(label: '正在退出...');
    try {
      await DsmApi().logout();
    } catch (_) {}
    loading();

    // 清除登录状态
    AppPreferences.remove('sid');
    AppPreferences.remove('smid');

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadWebViewEntries(); // Always read latest
    final theme = Theme.of(context);
    final server = DsmApi().server;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          child: const Text('我的'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 8.h),
        children: [
          // 服务器信息卡片
          if (server != null) _buildServerCard(theme, server),
          SizedBox(height: 16.h),

          // 通用设置
          _buildSectionTitle(theme, '通用设置'),
          _buildSettingCard(theme, [
            _buildNavTile(
              icon: Icons.workspace_premium_outlined,
              title: '我的权益',
              subtitle: '查看会员状态与套餐',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseDetailPage())),
            ),
            _buildNavTile(
              icon: Icons.dashboard_outlined,
              title: '仪表盘',
              subtitle: '查看服务器概览',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardPage())),
            ),
            _buildSwitchTile(
              icon: Icons.dark_mode_outlined,
              title: '深色模式',
              value: _darkMode,
              onChanged: _toggleDarkMode,
            ),
            _buildNavTile(
              icon: Icons.cleaning_services_outlined,
              title: '清理缓存',
              subtitle: _cacheSize == null ? '计算中...' : '图片和视频缓存 ${DsmApi.formatSize(_cacheSize!)}B',
              onTap: _clearCache,
            ),
          ]),
          SizedBox(height: 16.h),

          // 关于
          _buildSectionTitle(theme, '关于'),
          _buildSettingCard(theme, [
            _buildNavTile(
              icon: Icons.info_outline,
              title: '关于 Synology Cloud',
              subtitle: '版本 $_appVersion',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
            ),
          ]),
          SizedBox(height: 16.h),

          // 退出按钮
          SizedBox(
            height: 52.h,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withOpacity(0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: const Text('退出登录'),
            ),
          ),
          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  void _onTitleTap() {
    final now = DateTime.now();
    if (_titleFirstTap == null || now.difference(_titleFirstTap!) > const Duration(seconds: 3)) {
      _titleFirstTap = now;
      _titleTapCount = 1;
    } else {
      _titleTapCount += 1;
    }

    if (_titleTapCount >= 5) {
      _titleTapCount = 0;
      _titleFirstTap = null;
      DebugTools.activate();
    }
  }

  Widget _buildServerCard(ThemeData theme, ServerModel server) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalSettingsPage())),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        child: Padding(
          padding: EdgeInsets.all(16.aw),
          child: Row(
            children: [
              Container(
                width: 56.aw,
                height: 56.aw,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(
                  Icons.dns,
                  size: 28.aw,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(width: 16.aw),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.account,
                      style: TextStyle(
                        fontSize: 16.asp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      server.fullUrl,
                      style: TextStyle(
                        fontSize: 13.asp,
                        color: theme.hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (server.note.isNotEmpty)
                      Text(
                        server.note,
                        style: TextStyle(
                          fontSize: 12.asp,
                          color: theme.hintColor,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.check_circle, color: Colors.green, size: 20.aw),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: EdgeInsets.only(left: 4.aw, bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13.asp,
          fontWeight: FontWeight.w600,
          color: theme.hintColor,
        ),
      ),
    );
  }

  Widget _buildSettingCard(ThemeData theme, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
