import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/app_dialog.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_logger.dart';
import '../../utils/license_manager.dart';
import '../../utils/update_service.dart';
import 'announcement_page.dart';
import 'feedback_list_page.dart';

/// 关于页面：版本信息、开源许可、检查更新、诊断日志、微信入群、GitHub
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  static const String githubUrl = 'https://github.com/liuxingyuzaixian/synology_cloud_flutter';
  static const String wechatQrUrl = 'http://zhanglei.nasfuns.fun:4001/wechat-qr.png';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final versionStr = info.version;
      final buildNum = int.tryParse(info.buildNumber) ?? 0;
      if (mounted) setState(() => _appVersion = buildNum > 0 ? '$versionStr+$buildNum' : versionStr);
    } catch (_) {
      if (mounted) setState(() => _appVersion = '0.0.2'); // fallback
    }
  }

  void _viewLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'Synology Cloud',
      applicationVersion: _appVersion,
      applicationIcon: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: _buildAppIcon(48.aw),
      ),
    );
  }

  void _checkUpdate() => UpdateService.checkForUpdate(context, force: true);

  Future<void> _uploadDiagLog() async {
    final close = AppDialog.showLoading(label: '正在上传日志...');
    try {
      final ok = await AppLogger.upload(
        deviceId: LicenseManager().deviceId,
        remark: '用户从「关于」手动上传',
      );
      close();
      AppDialog.toast(ok ? '日志已上传，感谢配合' : '上传失败，请检查网络');
    } catch (e) {
      close();
      AppDialog.toast('上传失败：$e');
    }
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse(AboutPage.githubUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      AppDialog.toast('无法打开浏览器，已复制链接');
      await Clipboard.setData(const ClipboardData(text: AboutPage.githubUrl));
    }
  }

  Future<void> _copyGithubUrl() async {
    await Clipboard.setData(const ClipboardData(text: AboutPage.githubUrl));
    AppDialog.toast('GitHub 地址已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('关于 Synology Cloud')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 8.h),
        children: [
          // 应用信息
          SizedBox(height: 24.h),
          Center(child: _buildAppIcon(72.aw)),
          SizedBox(height: 12.h),
          Center(
            child: Text(
              'Synology Cloud',
              style: TextStyle(fontSize: 20.asp, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 4.h),
          Center(
            child: Text(
              '版本 $_appVersion',
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ),
          SizedBox(height: 8.h),
          Center(
            child: Text(
              '群晖 NAS 云助手，提供照片管理、文件浏览、系统监控等功能。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ),
          SizedBox(height: 24.h),

          // 常用操作
          _buildSettingCard(theme, [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('View licenses'),
              subtitle: Text('查看开源许可', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.asp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _viewLicenses,
            ),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('检查更新'),
              subtitle: Text('点击检测最新版本', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.asp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checkUpdate,
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('上传诊断日志'),
              subtitle: Text('协助开发者排查问题', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.asp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _uploadDiagLog,
            ),
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('开发计划与公告'),
              subtitle: Text('查看最新计划与更新说明', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.asp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnnouncementPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('意见反馈'),
              subtitle: Text('提交建议并查看处理结果', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.asp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FeedbackListPage()),
              ),
            ),
          ]),
          SizedBox(height: 16.h),

          // 微信入群
          _buildSettingCard(theme, [
            Padding(
              padding: EdgeInsets.all(16.aw),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 20.aw, color: theme.colorScheme.primary),
                      SizedBox(width: 8.aw),
                      Text(
                        '微信扫码入群',
                        style: TextStyle(fontSize: 15.asp, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: CachedNetworkImage(
                      imageUrl: AboutPage.wechatQrUrl,
                      width: 200.aw,
                      height: 200.aw,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 200.aw,
                        height: 200.aw,
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorBuilder: (_, _, _) => Container(
                        width: 200.aw,
                        height: 200.aw,
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Text(
                          '二维码加载失败\n请检查网络后重试',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    '扫码加入用户交流群，反馈问题、获取最新动态',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ]),
          SizedBox(height: 16.h),

          // GitHub
          _buildSettingCard(theme, [
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('GitHub 开源地址'),
              subtitle: Text(
                AboutPage.githubUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.asp),
              ),
              trailing: IconButton(
                icon: Icon(Icons.copy, size: 18.aw),
                tooltip: '复制链接',
                onPressed: _copyGithubUrl,
              ),
              onTap: _openGithub,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.aw, 0, 16.aw, 12.h),
              child: Row(
                children: [
                  Icon(Icons.star_border, size: 16.aw, color: Colors.amber),
                  SizedBox(width: 6.aw),
                  Expanded(
                    child: Text(
                      '欢迎 Star！截图联系作者可领取权益',
                      style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  Widget _buildAppIcon(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(Icons.cloud, color: Colors.white, size: size * 0.58),
    );
  }

  Widget _buildSettingCard(ThemeData theme, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
