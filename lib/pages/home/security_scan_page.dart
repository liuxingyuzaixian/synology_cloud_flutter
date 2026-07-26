import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

/// 安全顾问页面
class SecurityScanPage extends StatefulWidget {
  const SecurityScanPage({super.key});

  @override
  State<SecurityScanPage> createState() => _SecurityScanPageState();
}

class _SecurityScanPageState extends State<SecurityScanPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 系统状态
  bool _loading = true;
  String _sysStatus = '';
  int _sysProgress = 0;
  String _lastScanTime = '';
  String _startTime = '';
  Map<String, dynamic> _systemItems = {};

  // 规则列表
  List<Map<String, dynamic>> _rules = [];
  bool _ruleUpdating = true;

  static const Map<String, Color> _statusColors = {
    'safe': Colors.green,
    'risk': Colors.red,
    'warning': Colors.orange,
    'info': Colors.orangeAccent,
    'outOfDate': Colors.amber,
  };

  static const Map<String, String> _statusTexts = {
    'safe': '良好',
    'risk': '有风险',
    'warning': '警告',
    'info': '信息',
    'outOfDate': '版本过旧',
    'running': '正在扫描',
    'stop': '正在停止',
    'update': '正在更新',
  };

  static const Map<String, IconData> _statusIcons = {
    'safe': Icons.check_circle,
    'risk': Icons.error,
    'warning': Icons.warning_amber,
    'info': Icons.info,
    'outOfDate': Icons.update,
  };

  static const Map<String, int> _severities = {
    'risk': 0,
    'danger': 1,
    'warning': 2,
    'outOfDate': 3,
    'info': 4,
  };

  static const Map<String, int> _statuses = {
    'running': 0,
    'fail': 1,
    'pass': 2,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });
    try {
      final api = DsmApi();

      // 获取规则列表
      final ruleRes = await api.securityRuleGet();
      if (ruleRes['success'] == true) {
        final ruleItems = Map<String, dynamic>.from(ruleRes['data']['items'] ?? {});
        ruleItems.removeWhere((key, value) => value['status'] == 'skip');
        final rules = ruleItems.values.cast<Map<String, dynamic>>().toList();
        for (final element in rules) {
          element['severity'] = _severities[element['severity']] ?? 4;
          element['status'] = _statuses[element['status']] ?? 1;
        }
        rules.sort((v1, v2) {
          try {
            if (v1['status'] > v2['status']) return 1;
            if (v1['status'] < v2['status']) return -1;
            if (v1['severity'] > v2['severity']) return 1;
            if (v1['severity'] < v2['severity']) return -1;
            return 0;
          } catch (_) {
            return 0;
          }
        });
        setState(() {
          _rules = rules;
          _ruleUpdating = ruleRes['data']['isUpdating'] ?? false;
        });
      }

      // 获取系统状态
      final systemRes = await api.securitySystemGet();
      if (systemRes['success'] == true) {
        setState(() {
          _loading = false;
          _systemItems = Map<String, dynamic>.from(systemRes['data']['items'] ?? {});
          _lastScanTime = systemRes['data']['lastScanTime'] ?? '';
          _startTime = systemRes['data']['startTime'] ?? '';
          _sysProgress = systemRes['data']['sysProgress'] ?? 0;
          _sysStatus = systemRes['data']['sysStatus'] ?? '';
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _formatTimeAgo(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      final timestamp = int.parse(timeStr) * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 30) return '${diff.inDays}天前';
      return '${dt.year}/${dt.month}/${dt.day}';
    } catch (_) {
      return timeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('安全顾问'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '总览'),
            Tab(text: '结果'),
            Tab(text: '规则详情'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildResultsTab(),
                _buildRulesTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    final theme = Theme.of(context);
    final statusColor = _statusColors[_sysStatus] ?? Colors.grey;
    final statusIcon = _statusIcons[_sysStatus] ?? Icons.help;
    final statusText = _statusTexts[_sysStatus] ?? '未知状态';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.all(16.aw),
        children: [
          // 系统状态卡片
          Card(
            child: Padding(
              padding: EdgeInsets.all(20.aw),
              child: Row(
                children: [
                  if (_sysStatus == 'running')
                    SizedBox(
                      width: 60.w,
                      height: 60.w,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: _sysProgress / 100,
                            strokeWidth: 6,
                            color: _sysProgress < 90 ? Colors.blue : Colors.green,
                          ),
                          Text(
                            '$_sysProgress%',
                            style: TextStyle(
                              fontSize: 12.asp,
                              fontWeight: FontWeight.bold,
                              color: _sysProgress < 90 ? Colors.blue : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Icon(statusIcon, size: 50.r, color: statusColor),
                  16.wGap,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 18.asp,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        4.hGap,
                        Text(
                          _getSystemStatusDesc(),
                          style: TextStyle(fontSize: 14.asp, color: theme.hintColor),
                        ),
                        4.hGap,
                        if (_lastScanTime.isNotEmpty)
                          Text(
                            '上次扫描：${_formatTimeAgo(_lastScanTime)}',
                            style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
                          )
                        else if (_startTime.isNotEmpty)
                          Text(
                            '已运行：${_getRunningTime()}',
                            style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          16.hGap,
          // 各分类结果
          if (_systemItems.isNotEmpty) ...[
            _buildCategoryCard('malware', '恶意软件'),
            12.hGap,
            _buildCategoryCard('systemCheck', '系统检查'),
            12.hGap,
            _buildCategoryCard('userInfo', '用户信息'),
            12.hGap,
            _buildCategoryCard('network', '网络'),
            12.hGap,
            _buildCategoryCard('update', '更新'),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryCard(String key, String title) {
    final data = _systemItems[key];
    if (data == null || data is! Map) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.help_outline, color: Colors.grey),
          title: Text(title),
          subtitle: const Text('暂无数据'),
        ),
      );
    }

    final progress = data['progress'] ?? 0;
    final failSeverity = data['failSeverity'] ?? 'safe';
    final color = _statusColors[failSeverity] ?? Colors.green;
    final fail = data['fail'] as Map? ?? {};

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.aw),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16.asp, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (progress == 100)
                  Icon(_statusIcons[failSeverity] ?? Icons.check_circle, color: color, size: 24.r)
                else
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      value: progress / 100,
                      strokeWidth: 3,
                      color: progress < 90 ? Colors.blue : Colors.green,
                    ),
                  ),
              ],
            ),
            8.hGap,
            if (progress == 100) ...[
              if (failSeverity == 'safe')
                Text(
                  '检查通过',
                  style: TextStyle(color: Colors.green, fontSize: 14.asp),
                )
              else
                ...fail.entries.where((e) => e.value > 0).map((e) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 2.h),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(color: _statusColors[e.key] ?? Colors.orange, fontSize: 14.asp),
                    ),
                  );
                }),
            ] else
              Text(
                '扫描中... $progress%',
                style: TextStyle(color: Colors.blue, fontSize: 14.asp),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsTab() {
    if (_rules.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64.r, color: Colors.green),
            16.hGap,
            Text('所有检查项均通过', style: TextStyle(fontSize: 16.asp)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: EdgeInsets.all(16.aw),
        itemCount: _rules.length,
        itemBuilder: (context, index) {
          final rule = _rules[index];
          final status = rule['status'] ?? 1;
          final strId = (rule['strId'] ?? '').toString().replaceAll('_v2', '');
          final title = _getRuleTitle(strId, status);

          return Card(
            margin: EdgeInsets.only(bottom: 8.h),
            child: ListTile(
              leading: status == 2
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : status == 0
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.error, color: Colors.red),
              title: Text(
                title,
                style: TextStyle(fontSize: 14.asp),
              ),
              subtitle: Text(
                status == 2 ? '通过' : status == 0 ? '扫描中...' : '未通过',
                style: TextStyle(
                  fontSize: 12.asp,
                  color: status == 2 ? Colors.green : status == 0 ? Colors.blue : Colors.red,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRulesTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.all(16.aw),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.aw),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '安全扫描规则',
                    style: TextStyle(fontSize: 16.asp, fontWeight: FontWeight.bold),
                  ),
                  8.hGap,
                  Text(
                    '共 ${_rules.length} 条规则',
                    style: TextStyle(fontSize: 14.asp, color: Theme.of(context).hintColor),
                  ),
                  4.hGap,
                  if (_ruleUpdating)
                    Text(
                      '规则更新中...',
                      style: TextStyle(fontSize: 12.asp, color: Colors.orange),
                    ),
                ],
              ),
            ),
          ),
          12.hGap,
          ..._rules.map((rule) {
            final status = rule['status'] ?? 1;
            final severity = rule['severity'] ?? 4;
            final strId = (rule['strId'] ?? '').toString().replaceAll('_v2', '');
            return Card(
              margin: EdgeInsets.only(bottom: 6.h),
              child: ListTile(
                dense: true,
                leading: _getSeverityIcon(severity),
                title: Text(
                  _getRuleTitle(strId, status),
                  style: TextStyle(fontSize: 13.asp),
                ),
                trailing: status == 2
                    ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : status == 0
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.error, color: Colors.red, size: 20),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _getSeverityIcon(int severity) {
    if (severity <= 1) return const Icon(Icons.error, color: Colors.red, size: 20);
    if (severity == 2) return const Icon(Icons.warning, color: Colors.orange, size: 20);
    if (severity == 3) return const Icon(Icons.info, color: Colors.amber, size: 20);
    return const Icon(Icons.info_outline, color: Colors.grey, size: 20);
  }

  String _getRuleTitle(String strId, int status) {
    // 根据 strId 和 status 生成可读标题
    return _ruleNameMap[strId] ?? strId;
  }

  String _getSystemStatusDesc() {
    switch (_sysStatus) {
      case 'safe':
        return 'DSM 的安全性良好';
      case 'risk':
        return '有安全风险需您注意';
      case 'warning':
        return '部分安全保护设置未启用';
      case 'running':
        return '正在进行扫描...';
      case 'stop':
        return '停止扫描...';
      case 'update':
        return '正在更新安全数据库...';
      default:
        return '未知状态';
    }
  }

  String _getRunningTime() {
    if (_startTime.isEmpty) return '';
    try {
      final start = int.parse(_startTime);
      final diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - start;
      if (diff < 60) return '$diff秒';
      if (diff < 3600) return '${diff ~/ 60}分钟';
      return '${diff ~/ 3600}小时${(diff % 3600) ~/ 60}分钟';
    } catch (_) {
      return '';
    }
  }

  // 常见规则 ID 到可读名称的映射
  static const Map<String, String> _ruleNameMap = {
    'malware': '恶意软件扫描',
    'systemCheck': '系统检查',
    'userInfo': '用户信息检查',
    'network': '网络检查',
    'update': '系统更新检查',
    'autoBlock': '自动封锁',
    'accountMaxTrial': '账户登录尝试限制',
    'twoFactorAuth': '两步验证',
    'passwordExpiry': '密码过期策略',
    'passwordStrength': '密码强度要求',
    'loginNotify': '登录通知',
    'backup': '备份保护',
    'antiVirus': '防病毒',
    'firewall': '防火墙',
    'https': 'HTTPS 连接',
    'ssh': 'SSH 服务',
    'telnet': 'Telnet 服务',
    'ftp': 'FTP 服务',
    'smb': 'SMB 服务',
    'webStation': 'Web Station',
    'sqlInjection': 'SQL 注入防护',
    'crossSiteScripting': '跨站脚本防护',
    'adminAccount': '管理员账户安全',
    'defaultAccount': '默认账户检查',
    'guestAccount': '访客账户',
    'autoUpdate': '自动更新',
    'dsmVersion': 'DSM 版本',
    'storage': '存储空间检查',
  };
}
