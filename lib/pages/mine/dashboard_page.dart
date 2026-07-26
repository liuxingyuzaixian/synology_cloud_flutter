import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../app.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_preferences.dart';
import '../../utils/fly_router.dart';
import '../../models/webview_entry.dart';
import '../common/webview_page.dart';
import '../home/add_webview_page.dart';

/// 仪表盘页面 —— 群晖 NAS 系统概览
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  static const routeName = '/dashboard';

  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> with RouteAware {
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
        // 无权限的模块在 build 里直接不渲染（见 _buildBody），不弹错误/重试页
        // （错误页仅保留给批量请求失败/抛异常）。
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

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    _loadAppEntries(); // Always read latest from storage
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('服务器信息')),
      body: _buildBody(theme),
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
          // 系统信息卡（无系统信息权限则隐藏）
          if (_system.isNotEmpty) ...[
            _buildSystemInfoCard(theme),
            12.hGap,
          ],

          // CPU / 内存 + 网络（均依赖 Utilization，无权限则隐藏）
          if (_utilization != null) ...[
            _buildUsageRow(theme),
            12.hGap,
            _buildNetworkCard(theme),
            12.hGap,
          ],

          // 存储信息卡（无卷信息则隐藏）
          if (_volumes.isNotEmpty) ...[
            _buildStorageCard(theme),
            12.hGap,
          ],

          // 快捷操作卡（重启/关机需管理员，无系统权限则隐藏）
          if (_system.isNotEmpty) ...[
            _buildQuickActionsCard(theme),
            12.hGap,
          ],

          // 所有数据模块都无权限时的提示（非错误页，无重试按钮）
          if (_system.isEmpty && _utilization == null && _volumes.isEmpty)
            _buildNoPermissionHint(theme),

          // 底部间距
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8.h),
        ],
      ),
    );
  }

  // ---- 无权限占位提示（区别于错误页：不是加载失败，而是当前账号无权限）----
  Widget _buildNoPermissionHint(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 48.r, color: theme.hintColor),
          16.hGap,
          Text(
            '当前账号无权限查看服务器信息',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
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

  // ==================== 系统信息卡 ====================

  Widget _buildSystemInfoCard(ThemeData theme) {
    final model = _system['model']?.toString() ?? '-';
    final dsmVersion = _system['firmware_ver']?.toString() ?? '-';
    final upTime = _system['up_time']?.toString() ?? '';
    final sysTemp = _system['sys_temp'];
    final tempWarning = _system['temperature_warning'];

    return _DashboardCard(
      icon: Icons.dns_outlined,
      title: _hostname.isNotEmpty ? _hostname : 'Synology NAS',
      child: Column(
        children: [
          _infoRow(theme, '型号', model),
          _infoRow(theme, 'DSM 版本', dsmVersion),
          if (upTime.isNotEmpty)
            _infoRow(theme, '运行时间', DsmApi.parseUpTime(upTime)),
          if (sysTemp != null)
            _infoRow(
              theme,
              '温度',
              '$sysTemp°C',
              valueColor: (tempWarning == true || (sysTemp is num && sysTemp > 80))
                  ? Colors.red
                  : Colors.green,
            ),
        ],
      ),
    );
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

  // ==================== CPU / 内存 ====================

  Widget _buildUsageRow(ThemeData theme) {
    final cpuLoad = _getCpuPercent();
    final memUsage = _getMemoryPercent();
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW > 600;
    // On wide screens (tablet landscape), show side by side horizontally
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCircularGauge(theme, 'CPU', cpuLoad, Colors.blue)),
          12.wGap,
          Expanded(child: _buildCircularGauge(theme, '内存', memUsage, Colors.teal)),
        ],
      );
    }
    return Column(
      children: [
        _buildCircularGauge(theme, 'CPU', cpuLoad, Colors.blue),
        12.hGap,
        _buildCircularGauge(theme, '内存', memUsage, Colors.teal),
      ],
    );
  }

  Widget _buildCircularGauge(
    ThemeData theme,
    String label,
    double percent,
    Color color,
  ) {
    final clampedPercent = percent.clamp(0.0, 100.0);
    final displayPercent = clampedPercent.toStringAsFixed(0);
    final screenW = MediaQuery.of(context).size.width;
    final gaugeSize = screenW > 600 ? 130.r : 90.r;

    return _DashboardCard(
      icon: label == 'CPU' ? Icons.memory_outlined : Icons.storage_outlined,
      title: label,
      child: Padding(
        padding: EdgeInsets.only(top: 8.h, bottom: 4.h),
        child: Center(
          child: SizedBox(
            width: gaugeSize,
            height: gaugeSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90.r,
                  height: 90.r,
                  child: CustomPaint(
                    painter: _CircularGaugePainter(
                      percent: clampedPercent / 100,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                      strokeWidth: 8.r,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$displayPercent%',
                      style: TextStyle(
                        fontSize: 20.asp,
                        fontWeight: FontWeight.w700,
                        color: clampedPercent > 90
                            ? Colors.red
                            : clampedPercent > 70
                                ? Colors.orange
                                : color,
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 网络信息卡 ====================

  Widget _buildNetworkCard(ThemeData theme) {
    final txSpeed = _getNetworkTx();
    final rxSpeed = _getNetworkRx();

    return _DashboardCard(
      icon: Icons.wifi_outlined,
      title: '网络',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _speedIndicator(
                  theme,
                  icon: Icons.arrow_upward_rounded,
                  label: '上传',
                  speed: txSpeed,
                  color: Colors.blue,
                ),
              ),
              12.wGap,
              Expanded(
                child: _speedIndicator(
                  theme,
                  icon: Icons.arrow_downward_rounded,
                  label: '下载',
                  speed: rxSpeed,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          12.hGap,
          // Mini sparkline for network history
          SizedBox(
            height: 40.h,
            child: CustomPaint(
              painter: _NetworkSparkPainter(
                history: _networkHistory,
                txColor: Colors.blue.withValues(alpha: 0.5),
                rxColor: Colors.green.withValues(alpha: 0.5),
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedIndicator(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required int speed,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.aw),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.r, color: color),
              4.wGap,
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ],
          ),
          4.hGap,
          Text(
            '${DsmApi.formatSize(speed)}/s',
            style: TextStyle(
              fontSize: 14.asp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 存储信息卡 ====================

  Widget _buildStorageCard(ThemeData theme) {
    return _DashboardCard(
      icon: Icons.folder_outlined,
      title: '存储空间',
      child: _volumes.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Text('暂无存储空间信息', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            )
          : Column(
              children: _volumes.map((vol) => _buildVolumeItem(theme, vol)).toList(),
            ),
    );
  }

  Widget _buildVolumeItem(ThemeData theme, dynamic volume) {
    final size = volume['size'] as Map<String, dynamic>? ?? {};
    final totalStr = size['total']?.toString() ?? '0';
    final usedStr = size['used']?.toString() ?? '0';

    final total = int.tryParse(totalStr) ?? 0;
    final used = int.tryParse(usedStr) ?? 0;
    final percent = total > 0 ? used / total : 0.0;
    final volId = volume['id']?.toString() ?? volume['num_id']?.toString() ?? '?';
    final status = volume['status']?.toString() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '存储空间 $volId',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (status.isNotEmpty) ...[
                8.wGap,
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.aw, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: status == 'normal' ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Text(
                    status == 'normal' ? '正常' : status,
                    style: TextStyle(
                      fontSize: 10.asp,
                      color: status == 'normal' ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
          6.hGap,
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6.h,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                percent > 0.9 ? Colors.red : percent > 0.7 ? Colors.orange : Colors.blue,
              ),
            ),
          ),
          4.hGap,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已用 ${DsmApi.formatSize(used)} / ${DsmApi.formatSize(total)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: percent > 0.9 ? Colors.red : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 快捷操作卡 ====================

  Widget _buildQuickActionsCard(ThemeData theme) {
    return _DashboardCard(
      icon: Icons.power_settings_new,
      title: '快捷操作',
      child: Wrap(
        spacing: 10.aw,
        runSpacing: 10.h,
        children: [
          _actionChip(theme, Icons.refresh, '重启', () => _doPowerAction('reboot', '重启')),
          _actionChip(theme, Icons.power_settings_new, '关机', () => _doPowerAction('shutdown', '关机')),
        ],
      ),
    );
  }

  Widget _actionChip(ThemeData theme, IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18.r),
      label: Text(label),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
    );
  }

  // ==================== 数据提取辅助 ====================

  double _getCpuPercent() {
    if (_utilization == null) return 0;
    final cpu = _utilization!['cpu'] as Map<String, dynamic>?;
    if (cpu == null) return 0;
    final userLoad = cpu['user_load'] ?? 0;
    final systemLoad = cpu['system_load'] ?? 0;
    return (userLoad is num ? userLoad.toDouble() : 0) +
        (systemLoad is num ? systemLoad.toDouble() : 0);
  }

  double _getMemoryPercent() {
    if (_utilization == null) return 0;
    final mem = _utilization!['memory'] as Map<String, dynamic>?;
    if (mem == null) return 0;
    final usage = mem['real_usage'];
    return usage is num ? usage.toDouble() : 0;
  }

  int _getNetworkTx() {
    if (_utilization == null) return 0;
    final net = _utilization!['network'] as List?;
    if (net == null || net.isEmpty) return 0;
    final first = net[0] as Map<String, dynamic>;
    final tx = first['tx'];
    return tx is num ? tx.toInt() : 0;
  }

  int _getNetworkRx() {
    if (_utilization == null) return 0;
    final net = _utilization!['network'] as List?;
    if (net == null || net.isEmpty) return 0;
    final first = net[0] as Map<String, dynamic>;
    final rx = first['rx'];
    return rx is num ? rx.toInt() : 0;
  }
}

// ==================== 自定义 Painter ====================

/// 圆形仪表盘 Painter
class _CircularGaugePainter extends CustomPainter {
  final double percent; // 0.0 ~ 1.0
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircularGaugePainter({
    required this.percent,
    required this.color,
    required this.backgroundColor,
    this.strokeWidth = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;

    // 背景圆环
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // 进度弧
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * percent.clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // 从顶部开始
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularGaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.color != color;
}

/// 网络历史迷你折线 Painter
class _NetworkSparkPainter extends CustomPainter {
  final List<Map<String, dynamic>> history;
  final Color txColor;
  final Color rxColor;

  _NetworkSparkPainter({
    required this.history,
    required this.txColor,
    required this.rxColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    // 找到最大值用于缩放
    double maxVal = 1;
    for (final h in history) {
      final tx = (h['tx'] as num?)?.toDouble() ?? 0;
      final rx = (h['rx'] as num?)?.toDouble() ?? 0;
      maxVal = max(maxVal, max(tx, rx));
    }

    _drawLine(canvas, size, maxVal, (h) => (h['tx'] as num?)?.toDouble() ?? 0, txColor);
    _drawLine(canvas, size, maxVal, (h) => (h['rx'] as num?)?.toDouble() ?? 0, rxColor);
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    double maxVal,
    double Function(Map<String, dynamic>) extractor,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final stepX = size.width / max(history.length - 1, 1);

    for (int i = 0; i < history.length; i++) {
      final x = i * stepX;
      final value = extractor(history[i]);
      final y = size.height - (value / maxVal * size.height * 0.9);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // 填充区域
    final fillPath = Path.from(path)
      ..lineTo((history.length - 1) * stepX, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(_NetworkSparkPainter oldDelegate) => true;
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
