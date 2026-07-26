import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../components/coming_soon.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

class ControlPanelPage extends StatefulWidget {
  const ControlPanelPage({super.key});
  @override
  State<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends State<ControlPanelPage> {
  final List<_Section> _sections = [
    _Section('文件共享', [
      _MenuItem('共享文件夹', Icons.folder_shared, 'share'),
      _MenuItem('用户与群组', Icons.people, 'users'),
    ]),
    _Section('连接性', [
      _MenuItem('网络', Icons.wifi, 'network'),
      _MenuItem('当前连接用户', Icons.people_alt_outlined, 'connected_users'),
      _MenuItem('外部访问', Icons.link, 'connection'),
      _MenuItem('终端机和SNMP', Icons.terminal, 'terminal'),
    ]),
    _Section('系统', [
      _MenuItem('信息中心', Icons.info_outline, 'info_center'),
    ]),
    _Section('服务', [
      _MenuItem('任务计划', Icons.schedule, 'scheduler'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('控制面板')),
      body: ListView.builder(
        padding: EdgeInsets.all(16.r),
        itemCount: _sections.length,
        itemBuilder: (ctx, si) {
          final section = _sections[si];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 4.w, top: si == 0 ? 0 : 16.h, bottom: 8.h),
                child: Text(section.title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                child: Column(
                  children: section.items.asMap().entries.map((entry) {
                    final item = entry.value;
                    final isLast = entry.key == section.items.length - 1;
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(item.icon, size: 28.r, color: Theme.of(context).colorScheme.primary),
                          title: Text(item.title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                          trailing: Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => _navigate(item),
                        ),
                        if (!isLast) Divider(height: 1, indent: 56.w),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  void _navigate(_MenuItem item) {
    switch (item.key) {
      case 'users':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _UserManagePage()));
        break;
      case 'share':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _ShareFolderPage()));
        break;
      case 'network':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _NetworkPage()));
        break;
      case 'scheduler':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _SchedulerPage()));
        break;
      case 'terminal':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _TerminalSettingsPage()));
        break;
      case 'connection':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonPage(title: '外部访问', message: 'DDNS 和反向代理功能开发中')));
        break;
      case 'connected_users':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _ConnectedUsersPage()));
        break;
      case 'info_center':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const _InfoCenterPage()));
        break;
    }
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  final String key;
  _MenuItem(this.title, this.icon, this.key);
}

class _Section {
  final String title;
  final List<_MenuItem> items;
  _Section(this.title, this.items);
}

// ── User Management ──
class _UserManagePage extends StatefulWidget {
  const _UserManagePage();
  @override
  State<_UserManagePage> createState() => _UserManagePageState();
}

class _UserManagePageState extends State<_UserManagePage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  List<dynamic> _users = [];
  List<dynamic> _groups = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        DsmApi().users(),
        DsmApi().userGroups(),
      ]);
      setState(() {
        _users = results[0]['data']?['users'] ?? results[0]['users'] ?? [];
        _groups = results[1]['data']?['groups'] ?? results[1]['groups'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户与群组'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: '用户账号'),
          Tab(text: '用户群组'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildUserList(),
              _buildGroupList(),
            ]),
    );
  }

  Widget _buildUserList() {
    if (_users.isEmpty) {
      return Center(child: Text('暂无用户数据', style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
    }
    return ListView.builder(
      padding: EdgeInsets.all(12.r),
      itemCount: _users.length,
      itemBuilder: (ctx, i) {
        final u = Map<String, dynamic>.from(_users[i]);
        final expired = u['expired']?.toString() ?? 'normal';
        final isNormal = expired == 'normal';
        final additional = u['additional'] as Map<String, dynamic>? ?? {};
        final email = additional['email']?.toString() ?? u['email']?.toString() ?? '';
        final description = additional['description']?.toString() ?? u['description']?.toString() ?? '';
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isNormal ? Colors.green.withAlpha(25) : Colors.red.withAlpha(25),
              child: Icon(Icons.person, color: isNormal ? Colors.green : Colors.red, size: 24.r),
            ),
            title: Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: isNormal ? Colors.green.withAlpha(25) : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(isNormal ? '正常' : '停用', style: TextStyle(fontSize: 10.sp, color: isNormal ? Colors.green : Colors.red)),
              ),
              SizedBox(width: 8.w),
              Expanded(child: Text(u['name'] ?? u['username'] ?? '', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500))),
            ]),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (email.isNotEmpty) Text(email, style: TextStyle(fontSize: 12.sp)),
                if (description.isNotEmpty) Text(description, style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
              ],
            ),
            trailing: Text(u['type'] ?? '', style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
          ),
        );
      },
    );
  }

  Widget _buildGroupList() {
    if (_groups.isEmpty) {
      return Center(child: Text('暂无群组数据', style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
    }
    return ListView.builder(
      padding: EdgeInsets.all(12.r),
      itemCount: _groups.length,
      itemBuilder: (ctx, i) {
        final g = Map<String, dynamic>.from(_groups[i]);
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.group, color: Theme.of(context).colorScheme.primary, size: 24.r),
            ),
            title: Text(g['name'] ?? '', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
            subtitle: Text(g['description'] ?? '', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
          ),
        );
      },
    );
  }
}

// ── Share Folder ──
class _ShareFolderPage extends StatefulWidget {
  const _ShareFolderPage();
  @override
  State<_ShareFolderPage> createState() => _ShareFolderPageState();
}

class _ShareFolderPageState extends State<_ShareFolderPage> {
  bool _loading = true;
  List<dynamic> _folders = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await DsmApi().shareCore();
      setState(() { _folders = res['data']?['shares'] ?? res['shares'] ?? res['data']?['folders'] ?? []; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('共享文件夹')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? Center(child: Text('暂无共享文件夹', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
              : ListView.builder(
                  padding: EdgeInsets.all(12.r),
                  itemCount: _folders.length,
                  itemBuilder: (ctx, i) {
                    final f = Map<String, dynamic>.from(_folders[i]);
                    return Card(
                      margin: EdgeInsets.only(bottom: 8.h),
                      child: ListTile(
                        leading: Icon(Icons.folder, size: 32.r, color: Colors.amber),
                        title: Text(f['name'] ?? f['path'] ?? '', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                        subtitle: Text(f['description'] ?? '', style: TextStyle(fontSize: 12.sp)),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Network ──
class _NetworkPage extends StatelessWidget {
  const _NetworkPage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络设置')),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi, size: 64.r, color: Colors.grey),
        12.hGap,
        Text('网络设置页面', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
        8.hGap,
        Text('暂未实现完整功能', style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
      ])),
    );
  }
}

// ── Scheduler ──
class _SchedulerPage extends StatefulWidget {
  const _SchedulerPage();
  @override
  State<_SchedulerPage> createState() => _SchedulerPageState();
}

class _SchedulerPageState extends State<_SchedulerPage> {
  bool _loading = true;
  List<dynamic> _tasks = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await DsmApi().taskScheduler();
      setState(() { _tasks = res['data']?['tasks'] ?? res['tasks'] ?? []; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务计划')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? Center(child: Text('暂无计划任务', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
              : ListView.builder(
                  padding: EdgeInsets.all(12.r),
                  itemCount: _tasks.length,
                  itemBuilder: (ctx, i) {
                    final t = Map<String, dynamic>.from(_tasks[i]);
                    return Card(
                      margin: EdgeInsets.only(bottom: 8.h),
                      child: ListTile(
                        leading: Icon(Icons.schedule, size: 32.r),
                        title: Text(t['name'] ?? t['id'] ?? '', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                        subtitle: Text(t['schedule'] ?? t['next_trigger_time'] ?? '', style: TextStyle(fontSize: 12.sp)),
                        trailing: Text(t['enabled'] == true ? '启用' : '禁用', style: TextStyle(fontSize: 11.sp, color: t['enabled'] == true ? Colors.green : Colors.grey)),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Terminal Settings ──
class _TerminalSettingsPage extends StatefulWidget {
  const _TerminalSettingsPage();
  @override
  State<_TerminalSettingsPage> createState() => _TerminalSettingsPageState();
}

class _TerminalSettingsPageState extends State<_TerminalSettingsPage> {
  bool _loading = true;
  bool _ssh = false;
  bool _telnet = false;
  int _port = 22;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await DsmApi().terminalInfo();
      final data = res['data'] ?? res;
      setState(() { _ssh = data['enable_ssh'] ?? false; _telnet = data['enable_telnet'] ?? false; _port = int.tryParse(data['ssh_port']?.toString() ?? '22') ?? 22; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('终端设置'), actions: [
        IconButton(icon: const Icon(Icons.save), onPressed: () async {
          final close = AppDialog.showLoading();
          try { await DsmApi().setTerminal(_ssh, _telnet, '$_port'); AppDialog.toast('已保存'); } catch (e) { AppDialog.toast('保存失败'); }
          close();
        }),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: EdgeInsets.all(16.r),
        children: [
          Card(child: SwitchListTile(title: const Text('启用 SSH'), value: _ssh, onChanged: (v) => setState(() => _ssh = v))),
          8.hGap,
          Card(child: SwitchListTile(title: const Text('启用 Telnet'), value: _telnet, onChanged: (v) => setState(() => _telnet = v))),
          8.hGap,
          Card(child: ListTile(
            title: const Text('SSH 端口'),
            trailing: SizedBox(width: 80.w, child: TextField(
              textAlign: TextAlign.center,
              controller: TextEditingController(text: '$_port'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _port = int.tryParse(v) ?? 22,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            )),
          )),
        ],
      ),
    );
  }
}

// ── Connected Users (当前连接用户) ──
class _ConnectedUsersPage extends StatefulWidget {
  const _ConnectedUsersPage();
  @override
  State<_ConnectedUsersPage> createState() => _ConnectedUsersPageState();
}

class _ConnectedUsersPageState extends State<_ConnectedUsersPage> {
  bool _loading = true;
  List<dynamic> _connections = [];
  final Set<int> _kicking = {}; // 正在踢断的连接 index

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DsmApi().currentConnection();
      final data = res['data'] ?? res;
      // 兼容两种响应格式: data['items'] 和 data['connections']
      setState(() {
        _connections = (data['items'] as List?) ?? (data['connections'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kickConnection(int index) async {
    final c = Map<String, dynamic>.from(_connections[index]);
    final who = c['who']?.toString() ?? '未知';
    final from = c['from']?.toString() ?? '-';

    final confirm = await AppDialog.dangerConfirm(
      title: '终止连接',
      message: '确认要终止 $who ($from) 的连接吗？',
      confirmText: '终止连接',
    );
    if (confirm != true) return;

    setState(() => _kicking.add(index));
    try {
      final res = await DsmApi().kickConnection({'who': c['who'], 'from': c['from']});
      if (res['success'] == true) {
        AppDialog.toast('连接已终止');
        _load();
      } else {
        AppDialog.toast('操作失败');
      }
    } catch (e) {
      AppDialog.toast('操作失败');
    }
    if (mounted) setState(() => _kicking.remove(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('当前连接用户'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _connections.isEmpty
              ? Center(child: Text('暂无连接用户', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: EdgeInsets.all(12.r),
                    itemCount: _connections.length,
                    itemBuilder: (ctx, i) {
                      final c = Map<String, dynamic>.from(_connections[i]);
                      final who = c['who']?.toString() ?? '未知';
                      final from = c['from']?.toString() ?? '-';
                      final type = c['type']?.toString() ?? '-';
                      final time = c['time']?.toString() ?? '-';
                      final descr = c['descr']?.toString() ?? '';
                      final isCurrent = c['is_current_connected'] == true;
                      final isKicking = _kicking.contains(i);
                      return Card(
                        margin: EdgeInsets.only(bottom: 8.h),
                        child: Padding(
                          padding: EdgeInsets.all(12.r),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 用户名 + 状态标签
                              Row(
                                children: [
                                  Icon(
                                    isCurrent ? Icons.person : Icons.person_outline,
                                    size: 20.r,
                                    color: isCurrent ? Colors.green : Colors.grey,
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      who,
                                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: isCurrent ? Colors.green.withAlpha(25) : Colors.grey.withAlpha(25),
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text(
                                      isCurrent ? '当前会话' : '在线',
                                      style: TextStyle(fontSize: 10.sp, color: isCurrent ? Colors.green : Colors.grey),
                                    ),
                                  ),
                                  if (!isCurrent) ...[
                                    SizedBox(width: 8.w),
                                    isKicking
                                        ? SizedBox(width: 18.r, height: 18.r, child: const CircularProgressIndicator(strokeWidth: 2))
                                        : IconButton(
                                            icon: Icon(Icons.link_off, size: 18.r, color: Colors.red),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            tooltip: '终止连接',
                                            onPressed: () => _kickConnection(i),
                                          ),
                                  ],
                                ],
                              ),
                              SizedBox(height: 8.h),
                              // 详细信息
                              Wrap(
                                spacing: 16.w,
                                runSpacing: 4.h,
                                children: [
                                  _infoChip(Icons.devices, type),
                                  _infoChip(Icons.location_on_outlined, from),
                                  _infoChip(Icons.access_time, time),
                                ],
                              ),
                              if (descr.isNotEmpty) ...[
                                SizedBox(height: 4.h),
                                Text(descr, style: TextStyle(fontSize: 12.sp, color: Theme.of(context).hintColor)),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.r, color: Colors.grey),
        SizedBox(width: 4.w),
        Text(text, style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
      ],
    );
  }
}

// ── Info Center ──
class _InfoCenterPage extends StatefulWidget {
  const _InfoCenterPage();
  @override
  State<_InfoCenterPage> createState() => _InfoCenterPageState();
}

class _InfoCenterPageState extends State<_InfoCenterPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  Map<String, dynamic> _system = {};
  Map<String, dynamic>? _network;
  List<dynamic> _volumes = [];
  List<dynamic> _disks = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        DsmApi().systemInfo(),
        DsmApi().networkInfo(),
        DsmApi().storage(),
      ]);
      setState(() {
        _system = (results[0]['data'] ?? {}) as Map<String, dynamic>;
        _network = results[1]['data'] as Map<String, dynamic>?;
        final storageData = results[2]['data'] ?? {};
        _volumes = storageData['volumes'] ?? [];
        _disks = storageData['disks'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('信息中心'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: '系统'), Tab(text: '网络'), Tab(text: '存储'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildSystemTab(),
              _buildNetworkTab(),
              _buildStorageTab(),
            ]),
    );
  }

  Widget _buildSystemTab() {
    final hostname = _system['hostname'] ?? '-';
    final model = _system['model'] ?? '-';
    final serial = _system['serial'] ?? '-';
    final version = _system['version_string'] ?? _system['version'] ?? '-';
    final uptime = _system['up_time'] ?? '-';
    final cpuModel = _system['cpu_model'] ?? _system['cpu_family'] ?? '-';
    final cpuCores = _system['cpu_cores'] ?? '-';
    final ram = _system['ram_size'] ?? '-';
    final usbDevs = _system['usb_dev'] as List? ?? [];

    return ListView(
      padding: EdgeInsets.all(16.r),
      children: [
        Card(child: Column(children: [
          _infoRow('主机名', hostname),
          _infoRow('型号', model),
          _infoRow('序列号', serial),
          _infoRow('系统版本', version),
          _infoRow('运行时间', uptime),
        ])),
        12.hGap,
        Card(child: Column(children: [
          _infoRow('CPU', cpuModel),
          _infoRow('核心数', cpuCores.toString()),
          _infoRow('内存', ram.toString()),
        ])),
        if (usbDevs.isNotEmpty) ...[
          12.hGap,
          Card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: EdgeInsets.all(12.r), child: Text('USB 设备', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600))),
              ...usbDevs.map((usb) => ListTile(
                leading: Icon(Icons.usb, size: 24.r, color: Colors.grey),
                title: Text(usb['product'] ?? usb['name'] ?? '未知', style: TextStyle(fontSize: 13.sp)),
                subtitle: Text(usb['vendor'] ?? '', style: TextStyle(fontSize: 11.sp)),
              )),
            ],
          )),
        ],
      ],
    );
  }

  Widget _buildNetworkTab() {
    final nifs = _network?['nif'] as List? ?? [];
    if (nifs.isEmpty) {
      return Center(child: Text('暂无网络信息', style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
    }
    return ListView.builder(
      padding: EdgeInsets.all(16.r),
      itemCount: nifs.length,
      itemBuilder: (ctx, i) {
        final nif = Map<String, dynamic>.from(nifs[i]);
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(12.r),
                child: Text('局域网 ${i + 1}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              ),
              _infoRow('MAC 地址', nif['mac']?.toString() ?? '-'),
              _infoRow('IP 地址', nif['addr']?.toString() ?? '-'),
              _infoRow('子网掩码', nif['mask']?.toString() ?? '-'),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStorageTab() {
    if (_volumes.isEmpty && _disks.isEmpty) {
      return Center(child: Text('暂无存储信息', style: TextStyle(fontSize: 14.sp, color: Colors.grey)));
    }
    return ListView(
      padding: EdgeInsets.all(16.r),
      children: [
        if (_volumes.isNotEmpty) ...[
          Text('存储空间', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          8.hGap,
          ..._volumes.map((v) => Card(
            margin: EdgeInsets.only(bottom: 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(12.r),
                  child: Text(v['display_name'] ?? v['name'] ?? '存储空间', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                ),
                _infoRow('状态', v['status']?.toString() ?? '-'),
                _infoRow('大小', DsmApi.formatSize((v['size'] ?? 0) as num)),
                _infoRow('已用', DsmApi.formatSize((v['used'] ?? 0) as num)),
                SizedBox(height: 8.h),
              ],
            ),
          )),
        ],
        if (_disks.isNotEmpty) ...[
          12.hGap,
          Text('硬盘', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          8.hGap,
          ..._disks.map((d) => Card(
            margin: EdgeInsets.only(bottom: 8.h),
            child: ListTile(
              leading: Icon(Icons.storage, size: 32.r, color: Colors.blue),
              title: Text(d['model'] ?? d['name'] ?? '未知', style: TextStyle(fontSize: 14.sp)),
              subtitle: Text('${d['serial'] ?? ''} | ${DsmApi.formatSize((d['size'] ?? 0) as num)}', style: TextStyle(fontSize: 12.sp)),
              trailing: Text(d['status'] ?? '', style: TextStyle(fontSize: 11.sp, color: d['status'] == 'normal' ? Colors.green : Colors.grey)),
            ),
          )),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 14.sp)),
        Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}
