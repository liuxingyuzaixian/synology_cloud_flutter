import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

/// 通知页面
class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key});

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  bool _loading = true;
  String? _error;
  Map<String, List> _notifyGroups = {};
  Map<String, dynamic> _notifyStrings = {};

  @override
  void initState() {
    super.initState();
    _loadNotifies();
  }

  Future<void> _loadNotifies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 先获取通知字符串模板
      final stringsRes = await DsmApi().notifyStrings();
      if (stringsRes['success'] == true) {
        _notifyStrings = stringsRes['data'] ?? {};
      }

      final res = await DsmApi().notify();
      if (res['success'] == true) {
        final data = res['data'];
        List notifies;
        if (data is List) {
          notifies = data;
        } else if (data is Map) {
          notifies = (data['notify'] as List?) ??
              (data['notifies'] as List?) ??
              (data['items'] as List?) ??
              [];
        } else {
          notifies = [];
        }
        _groupNotifies(notifies);
      } else {
        setState(() {
          _error = res['error']?['code']?.toString() ?? '加载失败';
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 使用模板格式化消息内容
  String _formatMsg(String msg, String notifyTitle) {
    try {
      final msgMap = json.decode(msg) as Map<String, dynamic>;
      // 查找对应的通知模板
      final templateEntry = _notifyStrings[notifyTitle];
      if (templateEntry != null && templateEntry is Map) {
        String template = templateEntry['msg'] ?? '';
        // 清理 HTML 标记
        template = template
            .replaceAll('%LINK_BEGIN%', '')
            .replaceAll('%LINK_END%', '')
            .replaceAll('%PRE_APP_LINK%', '')
            .replaceAll('%POST_APP_LINK%', '');
        // 移除 HTML 标签
        template = template.replaceAll(RegExp(r'<[^>]*>'), '');
        // 替换模板变量
        msgMap.forEach((key, value) {
          template = template.replaceAll(key, value.toString());
        });
        return template.trim();
      }
      // 没有模板，尝试提取有用信息
      return _extractReadable(msgMap);
    } catch (_) {
      return msg;
    }
  }

  /// 从消息 JSON 中提取可读信息
  String _extractReadable(Map<String, dynamic> msgMap) {
    final parts = <String>[];
    // 常见字段映射
    if (msgMap.containsKey('%HOSTNAME%')) parts.add('${msgMap['%HOSTNAME%']}');
    if (msgMap.containsKey('%SERVICE%')) parts.add('已通过 ${msgMap['%SERVICE%']}');
    if (msgMap.containsKey('%CLIENT_IP%')) parts.add('封锁 IP 地址 [${msgMap['%CLIENT_IP%']}]');
    if (msgMap.containsKey('%AUTOBLOCK_ATTEMPTS%')) parts.add('尝试次数: ${msgMap['%AUTOBLOCK_ATTEMPTS%']}');
    if (msgMap.containsKey('%AUTOBLOCK_TIME%')) parts.add('时间: ${msgMap['%AUTOBLOCK_TIME%']}');
    if (parts.isEmpty) {
      // 兜底：取所有值
      return msgMap.values.map((v) => v.toString()).join(', ');
    }
    return parts.join(' ');
  }

  void _groupNotifies(List notifies) {
    final groups = <String, List>{};
    for (final notify in notifies) {
      final msgs = notify['msg'] as List? ?? [];
      final contents = <String>[];
      final notifyTitle = notify['title'] ?? '';

      for (final msg in msgs) {
        if (msg is String) {
          final text = _formatMsg(msg, notifyTitle);
          if (text.isNotEmpty) contents.add(text);
        } else {
          final text = msg.toString();
          if (text.isNotEmpty) contents.add(text);
        }
      }
      notify['contents'] = contents;

      // 分组标题：优先使用模板中的标题，否则使用 className
      String groupTitle;
      final templateEntry = _notifyStrings[notifyTitle];
      if (templateEntry != null && templateEntry is Map && templateEntry['title'] != null) {
        groupTitle = templateEntry['title'];
      } else {
        groupTitle = notify['className'] == '' || notify['className'] == null
            ? notifyTitle
            : notify['className'];
      }
      groups.putIfAbsent(groupTitle, () => []).add(notify);
    }
    setState(() => _notifyGroups = groups);
  }

  Future<void> _clearAll() async {
    final confirmed = await AppDialog.confirm(
      title: '清除通知',
      message: '确定要清除所有通知吗？',
      confirmText: '全部清除',
    );
    if (!confirmed) return;

    final close = AppDialog.showLoading(label: '清除中...');
    try {
      final res = await DsmApi().clearNotify();
      close();
      if (res['success'] == true) {
        AppDialog.toast('清除成功');
        setState(() => _notifyGroups = {});
      } else {
        AppDialog.toast('清除失败');
      }
    } catch (e) {
      close();
      AppDialog.toast('清除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48.r, color: theme.colorScheme.error),
              16.hGap,
              Text(_error!, style: theme.textTheme.bodyLarge),
              16.hGap,
              FilledButton.icon(
                onPressed: _loadNotifies,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifyGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 64.aw, color: theme.hintColor),
            12.hGap,
            Text('暂无消息', style: TextStyle(color: theme.hintColor, fontSize: 15.asp)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(top: 12.h),
            children: _notifyGroups.entries.map((entry) {
              return _buildNotifyGroup(entry.key, entry.value);
            }).toList(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16.aw),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('全部清除'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotifyGroup(String groupName, List group) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 6.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          '$groupName（${group.length}）',
          style: TextStyle(fontSize: 16.asp, fontWeight: FontWeight.w600),
        ),
        children: group.map((notify) => _buildNotifyItem(notify)).toList(),
      ),
    );
  }

  Widget _buildNotifyItem(notify) {
    final theme = Theme.of(context);
    final contents = notify['contents'] as List? ?? [];
    final time = notify['time'];
    final timeStr = time is int
        ? _formatTime(DateTime.fromMillisecondsSinceEpoch(time * 1000))
        : '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeStr.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 4.h),
              child: Text(
                timeStr,
                style: TextStyle(fontSize: 12.asp, color: Colors.grey),
              ),
            ),
          ...contents.map((msg) {
            return Padding(
              padding: EdgeInsets.only(bottom: 2.h),
              child: Text(
                msg.toString(),
                style: TextStyle(fontSize: 14.asp, color: theme.colorScheme.onSurface),
              ),
            );
          }),
          Divider(height: 1.h, color: theme.dividerColor),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
