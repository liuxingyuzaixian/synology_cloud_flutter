import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:synology_cloud_flutter/pages/home/packages_page.dart';
import 'package:synology_cloud_flutter/pages/home/resource_monitor_page.dart';
import 'package:synology_cloud_flutter/pages/home/storage_page.dart';

import '../../app.dart';
import '../../components/app_dialog.dart';
import '../../components/coming_soon.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../../models/webview_entry.dart';
import '../../utils/app_preferences.dart';
import '../common/album_backup_page.dart';
import '../common/webview_page.dart';
import '../notes/note_list_page.dart';
import 'add_webview_page.dart';
import 'control_panel_page.dart';
import 'docker_page.dart';
import 'download_page.dart';
import 'notify_page.dart';
import 'security_scan_page.dart';

/// 首页
class HomePage extends StatefulWidget {
  final VoidCallback? onWebViewChanged;
  const HomePage({super.key, this.onWebViewChanged});

  static const routeName = '/dashboard';

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with RouteAware {
  // ---- 数据状态 ----
  bool _loading = true;
  String _errorMsg = '';

  // System
  Map<String, dynamic> _system = {};
  String _hostname = '';

  // Utilization
  Map<String, dynamic>? _utilization;

  // Storage
  List<dynamic> _volumes = [];
  List<dynamic> _disks = [];
  List<WebViewEntry> _webViewEntries = [];

  // Network history (for the mini sparkline)
  final List<Map<String, dynamic>> _networkHistory =
  List.generate(20, (_) => {'tx': 0, 'rx': 0});

  Timer? _autoRefreshTimer;

  // ---- 我的应用 (WebViewEntries) ----
  List<WebViewEntry> _appEntries = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
    _loadAppEntries();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when returning from a pushed route
    _loadAppEntries();
    setState(() {});
  }

  Future<void> _editWebViewEntry(WebViewEntry entry) async {
    final result = await Navigator.push<WebViewEntry>(
      context,
      MaterialPageRoute(builder: (_) => AddWebViewPage(entry: entry, existingEntries: _webViewEntries)),
    );
    if (result != null) {
      setState(() {
        final idx = _webViewEntries.indexWhere((e) => e.id == entry.id);
        if (idx >= 0) _webViewEntries[idx] = result;
      });
      _saveWebViewEntries();
    }
  }

  // ==================== 数据加载 ====================

  Future<void> _loadData() async {
    try {
      final res = await DsmApi().dashboardData();

      if (res['success'] != true) {
        // Entire batch request failed — only show error if we have no cached data
        if (_utilization == null && _system.isEmpty && _volumes.isEmpty) {
          if (mounted) {
            setState(() {
              _loading = false;
              _errorMsg = res['error']?['code']?.toString() ?? '加载失败';
            });
          }
        } else {
          // We have some cached data from a previous load, just stop loading
          if (mounted) setState(() => _loading = false);
        }
        return;
      }

      final List result = res['data']?['result'] ?? [];

      for (final item in result) {
        if (item['success'] != true) {
          // 子 API 失败（常为非管理员的权限错误 105/1006），跳过该模块即可。
          continue;
        }
        final api = item['api'] as String? ?? '';
        final data = item['data'] as Map<String, dynamic>? ?? {};

        switch (api) {
          case 'SYNO.Core.System.Utilization':
            _utilization = data;
            // 追加网络历史
            final netList = data['network'] as List?;
            if (netList != null && netList.isNotEmpty) {
              final first = netList[0] as Map<String, dynamic>;
              _networkHistory.add({'tx': first['tx'] ?? 0, 'rx': first['rx'] ?? 0});
              if (_networkHistory.length > 30) _networkHistory.removeAt(0);
            }
            break;

          case 'SYNO.Core.System':
            _system = data;
            _hostname = data['hostname'] ?? DsmApi().server?.note ?? '';
            break;

          case 'SYNO.Storage.CGI.Storage':
            _volumes = (data['volumes'] as List? ?? [])..sort((a, b) {
              final aId = a['num_id'] ?? 0;
              final bId = b['num_id'] ?? 0;
              return (aId is num ? aId.toInt() : 0)
                  .compareTo(bId is num ? bId.toInt() : 0);
            });
            _disks = data['disks'] as List? ?? [];
            break;
        }
      }

      if (mounted) {
        // 批量请求本身成功（success=true），子 API 的失败通常是逐模块的
        // 权限问题（非管理员账号会拿到 105/1006）。这不是“页面错误”，
        // 首页正文只是导航网格，无权限的模块不渲染对应数据即可，
        // 不弹错误/重试页（错误页仅保留给批量请求失败/抛异常）。
        setState(() {
          _loading = false;
          _errorMsg = '';
        });
      }
    } catch (e) {
      // Entire request threw — only show error if we have no cached data
      if (_utilization == null && _system.isEmpty && _volumes.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMsg = e.toString();
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadData();
    });
  }

  Future<void> _onRefresh() async {
    await _loadData();
    _loadAppEntries();
  }

  void _loadAppEntries() {
    final json = AppPreferences.getString('webview_entries');
    final entries = WebViewEntry.listFromStorage(json);
    _appEntries = entries.where((e) => !e.openAsTab).toList();
  }

  /// Save entries back to storage and refresh
  void _saveAppEntries(List<WebViewEntry> allEntries) {
    AppPreferences.putString('webview_entries', WebViewEntry.listToJson(allEntries));
    _loadAppEntries();
    setState(() {});
  }

  // ==================== 快捷操作 ====================

  Future<void> _doPowerAction(String method, String label) async {
    final isShutdown = method == 'shutdown';
    final confirmed = await AppDialog.dangerConfirm(
      title: isShutdown ? '关机' : '重启',
      message: isShutdown
          ? '是否对该设备执行关机操作？'
          : '是否对该设备执行重启操作？',
      confirmText: label,
    );
    if (!confirmed) return;

    final close = AppDialog.showLoading(label: '$label中...');
    try {
      await DsmApi().power(method, false);
      close();
      AppDialog.toast('$label指令已发送');
    } catch (e) {
      close();
      AppDialog.toast('操作失败: $e');
    }
  }

  Future<void> _addWebViewEntry() async {
    final entry = await Navigator.push<WebViewEntry>(
      context,
      MaterialPageRoute(builder: (_) => AddWebViewPage(existingEntries: _webViewEntries)),
    );
    if (entry != null) {
      setState(() => _webViewEntries.add(entry));
      _saveWebViewEntries();
      AppDialog.toast('已添加: ${entry.title}');
    }
  }

  void _saveWebViewEntries() {
    AppPreferences.putString('webview_entries', WebViewEntry.listToJson(_webViewEntries));
    widget.onWebViewChanged?.call();
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    _loadAppEntries(); // Always read latest from storage
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: '消息',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotifyPage()));
            },
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  void _manageWebViewEntries() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16.aw),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note),
                          SizedBox(width: 8.aw),
                          Text('管理自定义页面', style: TextStyle(fontSize: 18.asp, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _webViewEntries.isEmpty
                          ? Center(child: Text('暂无自定义页面', style: TextStyle(color: Theme.of(ctx).hintColor)))
                          : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: _webViewEntries.length,
                        itemBuilder: (ctx, index) {
                          final entry = _webViewEntries[index];
                          final isLocked = entry.hideUrl;
                          return ListTile(
                            leading: Icon(entry.openAsTab ? Icons.tab : Icons.open_in_new, size: 20),
                            title: Text(entry.title),
                            subtitle: isLocked
                                ? null
                                : Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isLocked)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _editWebViewEntry(entry);
                                    },
                                  ),
                                IconButton(
                                  icon: Icon(Icons.delete, size: 20, color: Theme.of(ctx).colorScheme.error),
                                  onPressed: () {
                                    setSheetState(() {
                                      _webViewEntries.removeAt(index);
                                    });
                                    setState(() {});
                                    _saveWebViewEntries();
                                    AppDialog.toast('已删除: ${entry.title}');
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
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

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMsg.isNotEmpty) {
      return _buildErrorView(theme);
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 12.h),
        children: [
          // 我的应用
          if (_appEntries.isNotEmpty) ...[
            _buildMyAppsSection(theme),
            12.hGap,
          ],
          // NAS 功能 - 按控制面板分类排版
          _buildSectionTitle(theme, 'NAS 功能'),
          _buildNasFunctionGrid(theme),
          16.hGap,
          // 自定义页面
          _buildSectionTitle(theme, '自定义页面'),
          _buildSettingCard(theme, [
            _buildNavTile(
              icon: Icons.sort,
              title: 'Tab 排序',
              subtitle: '拖拽调整底部导航栏 Tab 顺序',
              onTap: () => Navigator.pushNamed(context, '/tab-sort'),
            ),
            _buildNavTile(
              icon: Icons.add_circle_outline,
              title: '添加自定义页面',
              subtitle: '添加 WebView 页面到 Tab 或首页',
              onTap: _addWebViewEntry,
            ),
            if (_webViewEntries.isNotEmpty)
              _buildNavTile(
                icon: Icons.edit_outlined,
                title: '管理自定义页面',
                subtitle: '当前 ${_webViewEntries.length} 个页面',
                onTap: _manageWebViewEntries,
              ),
          ]),
          SizedBox(height: 16.h),
          // 底部间距
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8.h),
        ],
      ),
    );
  }

  // ==================== NAS 功能网格布局 ====================

  Widget _buildNasFunctionGrid(ThemeData theme) {
    final screenW = MediaQuery.of(context).size.width;
    final crossAxisCount = screenW > 600 ? 4 : 3;

    // 按控制面板分类组织功能
    final categories = [
      _FunctionCategory(
        icon: Icons.settings_outlined,
        name: '控制面板',
        subtitle: '系统设置',
        color: Colors.blue,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ControlPanelPage())),
      ),
      _FunctionCategory(
        icon: Icons.dashboard_outlined,
        name: '资源监控',
        subtitle: 'CPU/内存/网络',
        color: Colors.green,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResourceMonitorPage())),
      ),
      _FunctionCategory(
        icon: Icons.storage_outlined,
        name: '存储管理',
        subtitle: '磁盘/卷/SMART',
        color: Colors.orange,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoragePage())),
      ),
      _FunctionCategory(
        icon: Icons.download_outlined,
        name: '下载任务',
        subtitle: 'Download Station',
        color: Colors.purple,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadPage())),
      ),
      _FunctionCategory(
        icon: Icons.layers_outlined,
        name: '套件中心',
        subtitle: '管理套件',
        color: Colors.teal,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackagesPage())),
      ),
      _FunctionCategory(
        icon: Icons.terminal_outlined,
        name: 'SSH 终端',
        subtitle: '远程连接',
        color: Colors.red,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonPage(title: 'SSH 终端'))),
      ),
      _FunctionCategory(
        icon: Icons.view_in_ar_outlined,
        name: 'Docker',
        subtitle: '容器管理',
        color: Colors.cyan,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DockerPage())),
      ),
      _FunctionCategory(
        icon: Icons.backup_outlined,
        name: '照片备份',
        subtitle: '自动备份',
        color: Colors.amber,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlbumBackupPage())),
      ),
      _FunctionCategory(
        icon: Icons.security_outlined,
        name: '安全性',
        subtitle: '安全顾问',
        color: Colors.deepOrange,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScanPage())),
      ),
      _FunctionCategory(
        icon: Icons.notifications_outlined,
        name: '通知设置',
        subtitle: '系统通知',
        color: Colors.blueGrey,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotifyPage())),
      ),
      _FunctionCategory(
        icon: Icons.edit_note,
        name: '记事本',
        subtitle: '本地便签',
        color: Colors.indigo,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoteListPage())),
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(16.aw),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8.aw,
            mainAxisSpacing: 8.h,
            childAspectRatio: 1.0,  // 调整为正方形，避免溢出
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return _buildFunctionItem(theme, cat);
          },
        ),
      ),
    );
  }

  Widget _buildFunctionItem(ThemeData theme, _FunctionCategory cat) {
    return GestureDetector(
      onTap: cat.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: cat.color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,  // 添加这行，让 Column 根据内容自适应
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(8.r),  // 减小内边距
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                cat.icon,
                color: cat.color,
                size: 24.aw,  // 略微减小图标尺寸
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              cat.name,
              style: TextStyle(
                fontSize: 12.asp,  // 略微减小字体
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              cat.subtitle,
              style: TextStyle(
                fontSize: 9.asp,  // 略微减小字体
                color: Colors.grey[500],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 错误视图 ----
  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48.r, color: theme.colorScheme.error),
            16.hGap,
            Text(_errorMsg, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            16.hGap,
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _errorMsg = '';
                });
                _loadData();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 我的应用 ====================

  String _resolveBaseUrl(String url) {
    final base = DsmApi().baseUrl;
    if (base.isEmpty) return url;
    return url.replaceFirst('BASE_URL', base);
  }

  Widget _buildMyAppsSection(ThemeData theme) {
    return _DashboardCard(
      icon: Icons.apps,
      title: '我的应用',
      child: Wrap(
        spacing: 12.aw,
        runSpacing: 12.h,
        children: _appEntries.map((entry) {
          return GestureDetector(
            onTap: () {
              final resolvedUrl = DsmApi().resolveUrlWithAuth(_resolveBaseUrl(entry.url));
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WebViewPage(
                  title: entry.title,
                  url: resolvedUrl,
                  hideUrl: entry.hideUrl,
                ),
              ));
            },
            onLongPress: () => _showAppContextMenu(entry),
            child: SizedBox(
              width: 64.aw,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48.aw,
                    height: 48.aw,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.language,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24.aw,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    entry.title,
                    style: TextStyle(fontSize: 11.asp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showAppContextMenu(WebViewEntry entry) {
    final isLocked = entry.hideUrl;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(entry.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (!isLocked)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('编辑'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editAppEntry(entry);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete, color: Theme.of(ctx).colorScheme.error),
                title: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAppEntry(entry);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editAppEntry(WebViewEntry entry) async {
    final json = AppPreferences.getString('webview_entries');
    final allEntries = WebViewEntry.listFromStorage(json);
    final result = await Navigator.push<WebViewEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => AddWebViewPage(entry: entry, existingEntries: allEntries),
      ),
    );
    if (result != null) {
      final idx = allEntries.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) allEntries[idx] = result;
      _saveAppEntries(allEntries);
    }
  }

  void _deleteAppEntry(WebViewEntry entry) async {
    final confirm = await AppDialog.confirm(
      title: '删除应用',
      message: '确定要删除「${entry.title}」吗？',
      confirmText: '删除',
    );
    if (confirm != true) return;
    final json = AppPreferences.getString('webview_entries');
    final allEntries = WebViewEntry.listFromStorage(json);
    allEntries.removeWhere((e) => e.id == entry.id);
    _saveAppEntries(allEntries);
    AppDialog.toast('已删除: ${entry.title}');
  }

  Widget _infoRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          SizedBox(
            width: 72.aw,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 功能分类模型 ====================
class _FunctionCategory {
  final IconData icon;
  final String name;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _FunctionCategory({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}


// ==================== 仪表盘卡片组件 ====================
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[800]  // 深色模式用灰色
          : Colors.white,      // 浅色模式用白色
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20.r, color: theme.colorScheme.primary),
                8.wGap,
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
            12.hGap,
            child,
          ],
        ),
      ),
    );
  }
}
