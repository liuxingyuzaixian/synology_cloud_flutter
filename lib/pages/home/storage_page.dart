import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _storage = {};
  List<dynamic> _disks = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final sRes = await DsmApi().storage();
      final dRes = await DsmApi().diskInfo();
      setState(() {
        _storage = sRes['data'] ?? sRes;
        _disks = dRes['data']?['disks'] ?? dRes['disks'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _showSmart(String deviceId) async {
    final close = AppDialog.showLoading();
    try {
      final res = await DsmApi().smartData(deviceId);
      close();
      if (!mounted) return;
      final data = res['data'] ?? res;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text('SMART - $deviceId'),
        content: SizedBox(
          width: 0.8.sw, height: 0.5.sh,
          child: SingleChildScrollView(child: Text(data.toString(), style: TextStyle(fontSize: 12.sp, fontFamily: 'monospace'))),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ));
    } catch (e) {
      close();
      AppDialog.toast('获取 SMART 数据失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('存储管理'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 48.r, color: Colors.red),
                  10.hGap, Text(_error!, style: TextStyle(fontSize: 14.sp)),
                  10.hGap, FilledButton(onPressed: _refresh, child: const Text('重试')),
                ]))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: EdgeInsets.all(12.r),
                    children: [
                      Text('存储空间', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      8.hGap,
                      _buildVolumes(),
                      16.hGap,
                      Text('硬盘列表', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      8.hGap,
                      if (_disks.isEmpty)
                        Center(child: Padding(padding: EdgeInsets.all(32.r), child: Text('暂无硬盘数据', style: TextStyle(color: Colors.grey))))
                      else
                        ..._disks.map((d) => _buildDiskCard(Map<String, dynamic>.from(d))),
                    ],
                  ),
                ),
    );
  }

  Widget _buildVolumes() {
    final volumes = _storage['volumes'] ?? _storage['vol'] ?? [];
    if (volumes is! List || volumes.isEmpty) {
      return Card(child: Padding(padding: EdgeInsets.all(16.r), child: Text('暂无卷信息', style: TextStyle(color: Colors.grey))));
    }
    return Column(children: volumes.map((v) {
      final vol = Map<String, dynamic>.from(v);
      final total = _parseNum(vol['size']?['total'] ?? vol['total_size'] ?? 0);
      final used = _parseNum(vol['size']?['used'] ?? vol['used_size'] ?? 0);
      final pct = total > 0 ? (used / total * 100) : 0.0;
      return Card(
        margin: EdgeInsets.only(bottom: 8.h),
        child: Padding(
          padding: EdgeInsets.all(16.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.disc_full, size: 20.r),
                8.wGap,
                Text(vol['id'] ?? vol['name'] ?? '卷', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              ]),
              8.hGap,
              Container(
                height: 10.h,
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5.r)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: pct > 90 ? Colors.red : pct > 80 ? Colors.amber : Colors.green,
                      borderRadius: BorderRadius.circular(5.r),
                    ),
                  ),
                ),
              ),
              4.hGap,
              Text('${DsmApi.formatSize(used)} / ${DsmApi.formatSize(total)}', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
            ],
          ),
        ),
      );
    }).toList());
  }

  Widget _buildDiskCard(Map<String, dynamic> disk) {
    final health = disk['health'] ?? disk['status'] ?? 'unknown';
    final Color hColor = health == 'healthy' || health == 'Normal' ? Colors.green : health == 'unknown' ? Colors.grey : Colors.red;
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: Icon(Icons.album, size: 32.r, color: hColor),
        title: Text(disk['id'] ?? disk['name'] ?? '磁盘', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
        subtitle: Text('${disk['model'] ?? ''}  ${DsmApi.formatSize(_parseNum(disk['size_total'] ?? disk['size'] ?? 0))}', style: TextStyle(fontSize: 12.sp)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(color: hColor.withAlpha(30), borderRadius: BorderRadius.circular(4.r)),
            child: Text(health.toString(), style: TextStyle(fontSize: 11.sp, color: hColor)),
          ),
          4.wGap,
          IconButton(
            icon: Icon(Icons.monitor_heart, size: 20.r),
            onPressed: () => _showSmart(disk['id'] ?? disk['name'] ?? ''),
          ),
        ]),
      ),
    );
  }

  /// 安全将 dynamic 值转为 num（API 可能返回 string 或 num）
  num _parseNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}
