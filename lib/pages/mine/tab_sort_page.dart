import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../models/webview_entry.dart';
import '../../utils/app_preferences.dart';
import '../../utils/fly_router.dart';

class TabSortRouteModule extends FlyRouteModule {
  @override
  List<AppRoute> get routes => [
        AppRoute(name: '/tab-sort', builder: (_, __) => const TabSortPage()),
      ];
}

class TabSortPage extends StatefulWidget {
  const TabSortPage({super.key});

  @override
  State<TabSortPage> createState() => _TabSortPageState();
}

class _TabSortPageState extends State<TabSortPage> {
  /// "首页" 固定在最顶部
  static const _homeItem = _TabItem('home', '首页', Icons.home, true, false);

  /// 可排序/删除的 Tab (首页和我的之外的)
  late List<_TabItem> _items;

  /// "我的" 始终在最后
  static const _settingsItem = _TabItem('settings', '我的', Icons.person, true, false);

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  void _loadOrder() {
    // 所有可能的 Tab (不含首页和我的)
    final allAvailable = <_TabItem>[
      _TabItem('photos', '照片', Icons.photo, true, true),
      _TabItem('files', '文件', Icons.folder, true, true),
    ];

    // 动态 WebView Tab
    final json = AppPreferences.getString('webview_entries');
    final entries = WebViewEntry.listFromStorage(json);
    for (final e in entries.where((e) => e.openAsTab)) {
      allAvailable.add(_TabItem(e.id, e.title, Icons.language, false, true));
    }

    // 读取隐藏列表
    final hiddenJson = AppPreferences.getString('tab_hidden');
    final hidden = <String>{
      if (hiddenJson.isNotEmpty)
        ...?(() { try { return List<String>.from(jsonDecode(hiddenJson) as List); } catch (_) { return null; } })(),
    };

    // 读取保存的顺序
    final orderJson = AppPreferences.getString('tab_order');
    if (orderJson.isNotEmpty) {
      try {
        final order = List<String>.from(jsonDecode(orderJson) as List);
        final ordered = <_TabItem>[];
        final used = <String>{};
        for (final id in order) {
          // 跳过固定的首页和我的
          if (id == 'home' || id == 'settings') continue;
          final item = allAvailable.where((e) => e.id == id).firstOrNull;
          if (item != null && !hidden.contains(id)) {
            ordered.add(item);
            used.add(id);
          }
        }
        for (final item in allAvailable) {
          if (!used.contains(item.id) && !hidden.contains(item.id)) {
            ordered.add(item);
          }
        }
        _items = ordered;
      } catch (_) {
        _items = allAvailable.where((e) => !hidden.contains(e.id)).toList();
      }
    } else {
      _items = allAvailable.where((e) => !hidden.contains(e.id)).toList();
    }
  }

  void _save() {
    final order = _items.map((e) => e.id).toList();
    AppPreferences.putString('tab_order', jsonEncode(order));
    AppDialog.toast('Tab 顺序已保存');
  }

  void _reset() {
    setState(() {
      _items = [
        _TabItem('photos', '照片', Icons.photo, true, true),
        _TabItem('files', '文件', Icons.folder, true, true),
      ];
    });
    AppPreferences.remove('tab_order');
    AppPreferences.remove('tab_hidden');
    AppDialog.toast('已恢复默认');
  }

  void _deleteItem(int index) async {
    final item = _items[index];
    final confirmed = await AppDialog.confirm(
      title: '删除 Tab',
      message: '确定要移除「${item.label}」吗？\n移除后可在"添加自定义页面"中重新添加。',
      confirmText: '移除',
    );
    if (!confirmed) return;

    setState(() => _items.removeAt(index));

    // 保存隐藏列表
    final hiddenJson = AppPreferences.getString('tab_hidden');
    final hidden = <String>{
      if (hiddenJson.isNotEmpty)
        ...?(() { try { return List<String>.from(jsonDecode(hiddenJson) as List); } catch (_) { return null; } })(),
    };
    hidden.add(item.id);
    AppPreferences.putString('tab_hidden', jsonEncode(hidden.toList()));
    _save();
    AppDialog.toast('已移除: ${item.label}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tab 排序'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('恢复默认')),
        ],
      ),
      body: Column(
        children: [
          // "首页" 固定在顶部
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: ListTile(
              leading: Icon(_homeItem.icon, color: theme.colorScheme.primary),
              title: Text(_homeItem.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('固定在最前，不可移除', style: TextStyle(fontSize: 12.sp, color: theme.hintColor)),
              trailing: Icon(Icons.lock_outline, size: 18, color: theme.hintColor),
            ),
          ),

          // 可排序区域
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
              itemCount: _items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _items.removeAt(oldIndex);
                  _items.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  key: ValueKey(item.id),
                  margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Icon(item.icon,
                        color: item.isDefault ? theme.colorScheme.primary : theme.colorScheme.secondary),
                    title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      item.isDefault ? '默认 Tab' : '自定义 WebView Tab',
                      style: TextStyle(fontSize: 12.sp, color: theme.hintColor),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.canDelete)
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                            onPressed: () => _deleteItem(index),
                          ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // "我的" 固定在底部
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: ListTile(
              leading: Icon(_settingsItem.icon, color: theme.colorScheme.primary),
              title: Text(_settingsItem.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('固定在最后，不可移除', style: TextStyle(fontSize: 12.sp, color: theme.hintColor)),
              trailing: Icon(Icons.lock_outline, size: 18, color: theme.hintColor),
            ),
          ),

          // 保存按钮
          Padding(
            padding: EdgeInsets.all(16.w),
            child: SizedBox(
              width: double.infinity,
              height: 48.h,
              child: FilledButton(
                onPressed: _save,
                child: const Text('保存排序'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final String id;
  final String label;
  final IconData icon;
  final bool isDefault; // 首页/照片/文件/我的
  final bool canDelete;

  const _TabItem(this.id, this.label, this.icon, this.isDefault, this.canDelete);
}
