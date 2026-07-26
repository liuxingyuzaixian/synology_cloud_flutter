import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key});
  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

class _PackagesPageState extends State<PackagesPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;
  List<dynamic> _installed = [];
  List<dynamic> _available = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final iRes = await DsmApi().installedPackages();
      final aRes = await DsmApi().packages();
      setState(() {
        _installed = iRes['data']?['packages'] ?? iRes['packages'] ?? [];
        _available = aRes['data']?['packages'] ?? aRes['packages'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running': return Colors.green;
      case 'stopped': return Colors.grey;
      default: return Colors.blue;
    }
  }

  Future<void> _launch(String id, String app) async {
    final close = AppDialog.showLoading();
    try {
      await DsmApi().launchPackage(id, app, 'open');
      AppDialog.toast('已启动');
    } catch (e) {
      AppDialog.toast('启动失败: $e');
    }
    close();
  }

  Future<void> _uninstall(String id) async {
    final ok = await AppDialog.confirm(title: '确认卸载', message: '确定卸载此套件？');
    if (!ok) return;
    final close = AppDialog.showLoading();
    try {
      await DsmApi().uninstallPackageTask(id);
      AppDialog.toast('卸载任务已创建');
      _refresh();
    } catch (e) {
      AppDialog.toast('卸载失败: $e');
    }
    close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('套件中心'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: '已安装'), Tab(text: '可用套件')]),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48.r, color: Colors.red),
                  10.hGap, Text(_error!, style: TextStyle(fontSize: 14.sp)),
                  10.hGap, FilledButton(onPressed: _refresh, child: const Text('重试')),
                ]))
              : TabBarView(controller: _tab, children: [
                  _buildList(_installed, true),
                  _buildList(_available, false),
                ]),
    );
  }

  Widget _buildList(List<dynamic> items, bool installed) {
    if (items.isEmpty) return Center(child: Text(installed ? '暂无已安装套件' : '暂无可用套件', style: TextStyle(fontSize: 16.sp, color: Colors.grey)));
    return GridView.builder(
      padding: EdgeInsets.all(12.r),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 8.h, crossAxisSpacing: 8.w, childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final pkg = Map<String, dynamic>.from(items[i]);
        final status = pkg['status'] ?? pkg['additional']?['status'] ?? '';
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12.r),
            onTap: installed ? () => _launch(pkg['id'] ?? '', pkg['name'] ?? '') : null,
            onLongPress: installed ? () => _uninstall(pkg['id'] ?? '') : null,
            child: Padding(
              padding: EdgeInsets.all(8.r),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.apps, size: 36.r, color: _statusColor(status)),
                  8.hGap,
                  Text(pkg['name'] ?? pkg['display_name'] ?? '未知', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                  4.hGap,
                  if (installed && status.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(color: _statusColor(status).withAlpha(30), borderRadius: BorderRadius.circular(4.r)),
                      child: Text(status, style: TextStyle(fontSize: 10.sp, color: _statusColor(status))),
                    ),
                  if (!installed)
                    Text(pkg['version'] ?? '', style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
