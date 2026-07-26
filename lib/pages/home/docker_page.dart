import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class DockerPage extends StatefulWidget {
  const DockerPage({super.key});
  @override
  State<DockerPage> createState() => _DockerPageState();
}

class _DockerPageState extends State<DockerPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  String? _error;
  List<dynamic> _containers = [];
  List<dynamic> _images = [];

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
      final cRes = await DsmApi().dockerContainerInfo();
      final iRes = await DsmApi().dockerImageInfo();
      
      // Docker API 返回的是 compound 请求，结果在 data['result'] 数组中
      List containers = [];
      List images = [];
      Map<String, dynamic>? utilization;
      List registries = [];
      
      // 解析容器信息
      final cResult = cRes['data']?['result'] as List? ?? [];
      for (final item in cResult) {
        if (item['success'] == true) {
          switch (item['api']) {
            case 'SYNO.Core.System.Utilization':
              utilization = item['data'];
              break;
            case 'SYNO.Docker.Container':
              containers = item['data']?['containers'] ?? [];
              containers.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
              break;
            case 'SYNO.Docker.Container.Resource':
              // 合并资源信息到对应容器
              final resources = item['data']?['resources'] as List? ?? [];
              for (final resource in resources) {
                for (final container in containers) {
                  if (resource['name'] == container['name']) {
                    container['cpu'] = resource['cpu'] ?? 0;
                    container['memory'] = resource['memory'] ?? 0;
                    container['memoryPercent'] = resource['memoryPercent'] ?? 0;
                  }
                }
              }
              break;
          }
        }
      }
      
      // 解析镜像信息
      final iResult = iRes['data']?['result'] as List? ?? [];
      for (final item in iResult) {
        if (item['success'] == true) {
          switch (item['api']) {
            case 'SYNO.Docker.Image':
              images = item['data']?['images'] ?? [];
              images.sort((a, b) => (a['repository'] ?? '').compareTo(b['repository'] ?? ''));
              break;
            case 'SYNO.Docker.Registry':
              registries = item['data']?['registries'] ?? [];
              break;
          }
        }
      }
      
      setState(() {
        _containers = containers;
        _images = images;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running': return Colors.green;
      case 'stopped': case 'exited': return Colors.red;
      case 'paused': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Future<void> _powerAction(String name, String action) async {
    final close = AppDialog.showLoading();
    try {
      await DsmApi().dockerPower(name, action);
      AppDialog.toast('$action 成功');
      _refresh();
    } catch (e) {
      AppDialog.toast('操作失败: $e');
    }
    close();
  }

  void _showContainerActions(Map c) {
    final name = c['name'] ?? '';
    final status = c['status'] ?? '';
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (status != 'running') ListTile(
          leading: const Icon(Icons.play_arrow, color: Colors.green), title: const Text('启动'),
          onTap: () { Navigator.pop(ctx); _powerAction(name, 'start'); },
        ),
        if (status == 'running') ListTile(
          leading: const Icon(Icons.stop, color: Colors.red), title: const Text('停止'),
          onTap: () { Navigator.pop(ctx); _powerAction(name, 'stop'); },
        ),
        if (status == 'running') ListTile(
          leading: const Icon(Icons.refresh), title: const Text('重启'),
          onTap: () { Navigator.pop(ctx); _powerAction(name, 'restart'); },
        ),
        ListTile(
          leading: const Icon(Icons.delete, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)),
          onTap: () { Navigator.pop(ctx); _powerAction(name, 'delete'); },
        ),
        ListTile(
          leading: const Icon(Icons.article), title: const Text('查看日志'),
          onTap: () { Navigator.pop(ctx); _showLogs(name); },
        ),
      ]),
    ));
  }

  Future<void> _showLogs(String name) async {
    final close = AppDialog.showLoading();
    try {
      final res = await DsmApi().dockerLog(name, 'stdout');
      final logs = res['data']?['logs'] ?? res['logs'] ?? res.toString();
      close();
      if (!mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text('日志 - $name'),
        content: SizedBox(
          width: 0.8.sw, height: 0.5.sh,
          child: SingleChildScrollView(child: Text(logs is List ? logs.join('\n') : logs.toString(), style: TextStyle(fontSize: 12.sp, fontFamily: 'monospace'))),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ));
    } catch (e) {
      close();
      AppDialog.toast('获取日志失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Docker'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: '容器'), Tab(text: '镜像')]),
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
                  _buildContainerList(),
                  _buildImageList(),
                ]),
    );
  }

  Widget _buildContainerList() {
    if (_containers.isEmpty) return Center(child: Text('暂无容器', style: TextStyle(fontSize: 16.sp, color: Colors.grey)));
    return ListView.builder(
      padding: EdgeInsets.all(12.r),
      itemCount: _containers.length,
      itemBuilder: (ctx, i) {
        final c = Map<String, dynamic>.from(_containers[i]);
        final status = c['status'] ?? '';
        final cpu = c['cpu'] ?? 0;
        final mem = c['mem'] ?? 0;
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: InkWell(
            borderRadius: BorderRadius.circular(12.r),
            onLongPress: () => _showContainerActions(c),
            onTap: () => _showContainerActions(c),
            child: Padding(
              padding: EdgeInsets.all(12.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.circle, size: 10.r, color: _statusColor(status)),
                    8.wGap,
                    Expanded(child: Text(c['name'] ?? '未知', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600))),
                    Text(status, style: TextStyle(fontSize: 12.sp, color: _statusColor(status))),
                  ]),
                  6.hGap,
                  Text(c['image'] ?? '', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                  6.hGap,
                  Row(children: [
                    _miniChip(Icons.memory, 'CPU ${(cpu as num).toStringAsFixed(1)}%'),
                    8.wGap,
                    _miniChip(Icons.storage, 'MEM ${(mem as num).toStringAsFixed(1)}%'),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4.r)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12.r), 4.wGap, Text(label, style: TextStyle(fontSize: 11.sp)),
      ]),
    );
  }

  Widget _buildImageList() {
    if (_images.isEmpty) return Center(child: Text('暂无镜像', style: TextStyle(fontSize: 16.sp, color: Colors.grey)));
    return ListView.builder(
      padding: EdgeInsets.all(12.r),
      itemCount: _images.length,
      itemBuilder: (ctx, i) {
        final img = Map<String, dynamic>.from(_images[i]);
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: Icon(Icons.inventory_2, size: 32.r),
            title: Text(img['name'] ?? img['repository'] ?? '未知', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
            subtitle: Text('${img['tag'] ?? 'latest'}  |  ${DsmApi.formatSize((img['size'] ?? 0) as num)}', style: TextStyle(fontSize: 12.sp)),
            trailing: Text(img['id']?.toString().substring(0, 12) ?? '', style: TextStyle(fontSize: 11.sp, fontFamily: 'monospace')),
          ),
        );
      },
    );
  }
}
