import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class ResourceMonitorPage extends StatefulWidget {
  const ResourceMonitorPage({super.key});
  @override
  State<ResourceMonitorPage> createState() => _ResourceMonitorPageState();
}

class _ResourceMonitorPageState extends State<ResourceMonitorPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _util = {};
  List<dynamic> _processes = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uRes = await DsmApi().utilization();
      final pRes = await DsmApi().process();
      setState(() {
        _util = uRes['data'] ?? uRes;
        _processes = pRes['data']?['processes'] ?? pRes['processes'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  num _cpuUsage() {
    final cpu = _util['cpu'];
    if (cpu is Map) return (cpu['cpu_usage'] ?? cpu['user_load'] ?? 0) as num;
    return 0;
  }

  num _memUsage() {
    final mem = _util['memory'];
    if (mem is Map) {
      final total = (mem['memory_total'] ?? 1) as num;
      final used = (mem['memory_usage'] ?? mem['memory_used'] ?? 0) as num;
      return total > 0 ? (used / total * 100) : 0;
    }
    return 0;
  }

  num _netUp() {
    final net = _util['network'];
    if (net is Map) return (net[0]?['tx'] ?? net['tx'] ?? 0) as num;
    if (net is List && net.isNotEmpty) return (net[0]['tx'] ?? 0) as num;
    return 0;
  }

  num _netDown() {
    final net = _util['network'];
    if (net is Map) return (net[0]?['rx'] ?? net['rx'] ?? 0) as num;
    if (net is List && net.isNotEmpty) return (net[0]['rx'] ?? 0) as num;
    return 0;
  }

  Widget _usageBar(String label, num percent, IconData icon, Color color) {
    final p = (percent.toDouble()).clamp(0, 100);
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: Padding(
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 20.r, color: color),
              8.wGap,
              Text(label, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${p.toStringAsFixed(1)}%', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: color)),
            ]),
            8.hGap,
            Container(
              height: 12.h,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6.r)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: p / 100,
                child: Container(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6.r)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资源监控'), actions: [
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
                      Text('系统资源', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      8.hGap,
                      _usageBar('CPU 使用率', _cpuUsage(), Icons.memory, Colors.blue),
                      _usageBar('内存使用率', _memUsage(), Icons.storage, Colors.green),
                      Card(
                        margin: EdgeInsets.only(bottom: 8.h),
                        child: Padding(
                          padding: EdgeInsets.all(16.r),
                          child: Row(children: [
                            Expanded(child: Column(children: [
                              Icon(Icons.arrow_upward, size: 20.r, color: Colors.orange),
                              4.hGap,
                              Text('↑ ${DsmApi.formatSize(_netUp())}/s', style: TextStyle(fontSize: 13.sp)),
                            ])),
                            Expanded(child: Column(children: [
                              Icon(Icons.arrow_downward, size: 20.r, color: Colors.blue),
                              4.hGap,
                              Text('↓ ${DsmApi.formatSize(_netDown())}/s', style: TextStyle(fontSize: 13.sp)),
                            ])),
                          ]),
                        ),
                      ),
                      16.hGap,
                      Text('进程列表', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      8.hGap,
                      if (_processes.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(32.r),
                          child: Center(child: Text('暂无进程数据', style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ..._processes.take(20).map((p) {
                          final proc = Map<String, dynamic>.from(p);
                          return Card(
                            margin: EdgeInsets.only(bottom: 4.h),
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.circle, size: 8.r, color: Colors.green),
                              title: Text(proc['name'] ?? proc['pid']?.toString() ?? '', style: TextStyle(fontSize: 13.sp)),
                              subtitle: Text('PID: ${proc['pid'] ?? ''}', style: TextStyle(fontSize: 11.sp)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('CPU ${(proc['cpu'] ?? 0).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11.sp)),
                                  Text('MEM ${(proc['mem'] ?? 0).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11.sp)),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
