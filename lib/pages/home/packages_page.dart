import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';

/// 套件中心（参考旧版 dsm_helper 实现）
/// 4 个 Tab：已安装 / 全部套件 / 社群 / Beta（有 Beta 套件时显示）
class PackagesPage extends StatefulWidget {
  const PackagesPage({super.key});
  @override
  State<PackagesPage> createState() => _PackagesPageState();
}

class _PackagesPageState extends State<PackagesPage> with TickerProviderStateMixin {
  TabController? _tabController;

  // DSM 版本兼容（5.x/6.1 -> 1；6.2 -> installed=1/packages=2；7.x -> 均 2）
  int _packagesVersion = 2;
  int _installedVersion = 2;

  List _packages = []; // 全部套件（官方源）
  List _others = []; // 社群（第三方源）
  List _betas = []; // Beta 套件
  List _categories = [];
  List _installedPackagesInfo = []; // SYNO.Core.Package 原始数据
  List _installedPackages = []; // 合并后的已安装套件
  List _canUpdatePackages = []; // 可更新套件
  List _volumes = [];

  bool _loadingAll = true;
  bool _loadingInstalled = true;
  bool _loadingOthers = true;
  String? _error;

  /// 安装/更新中的套件 id -> 进度文案
  final Map<String, String> _taskText = {};
  final Map<String, Timer> _installTimers = {};
  Timer? _pollingTimer;

  // 搜索
  bool _searching = false;
  String _keyword = '';
  final TextEditingController _searchController = TextEditingController();

  List get _allPackages => [..._packages, ..._betas, ..._others];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(initialIndex: 0, length: 3, vsync: this);
    _init();
    // 已安装套件状态每 15s 轮询刷新
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_loadingInstalled) _getInstalledPackages();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    for (final t in _installTimers.values) {
      t.cancel();
    }
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _init() async {
    await _parseDsmVersion();
    await _getData();
  }

  /// 从系统信息解析 firmware_ver 决定 API 版本
  Future<void> _parseDsmVersion() async {
    try {
      final res = await DsmApi().systemInfo();
      final fw = res['data']?['firmware_ver']?.toString() ?? ''; // e.g. "DSM 7.2-64570"
      final match = RegExp(r'(\d+)\.(\d+)').firstMatch(fw);
      if (match != null) {
        final major = int.parse(match.group(1)!);
        final minor = int.parse(match.group(2)!);
        if (major == 5 || (major == 6 && minor == 1)) {
          _packagesVersion = 1;
          _installedVersion = 1;
        } else if (major == 6 && minor == 2) {
          _packagesVersion = 2;
          _installedVersion = 1;
        } else {
          _packagesVersion = 2;
          _installedVersion = 2;
        }
      }
    } catch (_) {
      // 解析失败保持默认（均为 2）
    }
  }

  Future<void> _getData() async {
    try {
      final res = await DsmApi().packages(version: _packagesVersion);
      if (res['success'] == true) {
        final data = res['data'] ?? {};
        _packages = data['packages'] ?? data['data'] ?? [];
        _categories = data['categories'] ?? [];
        final betas = data['beta_packages'] ?? [];
        if (mounted) {
          setState(() {
            if (betas is List && betas.isNotEmpty && _betas.isEmpty) {
              _betas = betas;
              final oldIndex = _tabController?.index ?? 0;
              _tabController?.dispose();
              _tabController = TabController(initialIndex: oldIndex, length: 4, vsync: this);
            } else if (betas is List) {
              _betas = betas;
            }
            _loadingAll = false;
            _error = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loadingAll = false;
            _error = '数据加载失败: ${res['error']?['code'] ?? '未知错误'}';
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAll = false;
          _error = e.toString();
        });
      }
      return;
    }
    _getOthers();
    _getInstalledPackages();
    _getVolumes();
  }

  Future<void> _getOthers() async {
    try {
      final res = await DsmApi().packages(others: true, version: _packagesVersion);
      if (res['success'] == true && mounted) {
        final data = res['data'] ?? {};
        setState(() {
          _others = data['packages'] ?? data['data'] ?? [];
          _loadingOthers = false;
        });
        _calcInstalledPackage();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOthers = false);
    }
  }

  Future<void> _getInstalledPackages() async {
    try {
      final res = await DsmApi().installedPackages(version: _installedVersion);
      if (res['success'] == true && mounted) {
        setState(() {
          _installedPackagesInfo = res['data']?['packages'] ?? [];
          _loadingInstalled = false;
        });
        _calcInstalledPackage();
      } else if (mounted) {
        setState(() => _loadingInstalled = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInstalled = false);
    }
  }

  Future<void> _getVolumes() async {
    try {
      final res = await DsmApi().volumes();
      if (res['success'] == true && mounted) {
        setState(() => _volumes = res['data']?['volumes'] ?? []);
      }
    } catch (_) {}
  }

  /// 合并已安装信息到套件列表，计算 installed/can_update/launched
  void _calcInstalledPackage() {
    final installed = [];
    final canUpdate = [];
    final matchedIds = <String>{};
    for (final info in _installedPackagesInfo) {
      for (final package in _allPackages) {
        package['installed'] = package['installed'] ?? false;
        package['installed_version'] = package['installed_version'] ?? '';
        package['can_update'] = package['can_update'] ?? false;
        package['launched'] = package['launched'] ?? false;
        if (info['id'] == package['id']) {
          matchedIds.add(info['id'].toString());
          package['installed'] = true;
          package['installed_version'] = info['version'];
          package['can_update'] = _versionCompare(
                  package['installed_version'].toString(), package['version'].toString()) <
              0;
          package['additional'] = info['additional'];
          installed.add(package);
          if (package['can_update'] == true) canUpdate.add(package);
          package['launched'] =
              info['additional'] != null && info['additional']['status'] == 'running';
        }
      }
    }
    // 服务器列表中没有的已安装套件（如手动安装的第三方套件）也展示出来
    for (final info in _installedPackagesInfo) {
      if (!matchedIds.contains(info['id'].toString())) {
        installed.add({
          'id': info['id'],
          'dname': info['name'] ?? info['id'],
          'version': info['version'],
          'installed': true,
          'installed_version': info['version'],
          'can_update': false,
          'launched': info['additional'] != null && info['additional']['status'] == 'running',
          'additional': info['additional'],
          'thumbnail': const [],
          'maintainer': info['additional']?['maintainer'] ?? '',
        });
      }
    }
    if (mounted) {
      setState(() {
        _installedPackages = installed;
        _canUpdatePackages = canUpdate;
      });
    }
  }

  /// 版本比较（与旧版逻辑一致：优先比较 build 号）
  static int _versionCompare(String v1, String v2) {
    try {
      final version1 = v1.split('-');
      final version2 = v2.split('-');
      if (version1.length > 1 && version2.length > 1) {
        return int.parse(version1[1]).compareTo(int.parse(version2[1]));
      }
      final names1 = version1[0].split('.');
      final names2 = version2[0].split('.');
      final minLength = names1.length < names2.length ? names1.length : names2.length;
      for (var i = 0; i < minLength; i++) {
        final diff = int.parse(names1[i]) - int.parse(names2[i]);
        if (diff != 0) return diff;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  List<String> _getCategoryName(dynamic categoryIds) {
    if (categoryIds is! List) return [];
    final names = <String>[];
    for (final id in categoryIds) {
      for (final category in _categories) {
        if (category['id'] == id) names.add(category['dname'].toString());
      }
    }
    return names;
  }

  // ==================== 套件操作 ====================

  String _dsmAppsOf(Map pkg) {
    return (pkg['dsm_apps'] ?? pkg['additional']?['dsm_apps'] ?? '').toString();
  }

  Future<void> _startPackage(Map pkg) async {
    final close = AppDialog.showLoading(label: '启动中...');
    try {
      final res = await DsmApi().launchPackage(pkg['id'], _dsmAppsOf(pkg), 'start');
      close();
      if (res['success'] == true) {
        AppDialog.toast('已启动');
        await _getInstalledPackages();
      } else {
        AppDialog.toast('启动失败: ${res['error']?['code'] ?? '未知错误'}');
      }
    } catch (e) {
      close();
      AppDialog.toast('启动失败: $e');
    }
  }

  Future<void> _stopPackage(Map pkg) async {
    final confirmed = await AppDialog.dangerConfirm(
      title: '停用套件',
      message: '确认要停用「${pkg['dname']}」？',
      confirmText: '停用',
    );
    if (!confirmed) return;
    final close = AppDialog.showLoading(label: '停用中...');
    try {
      final res = await DsmApi().launchPackage(pkg['id'], _dsmAppsOf(pkg), 'stop');
      close();
      if (res['success'] == true) {
        AppDialog.toast('已停用');
        await _getInstalledPackages();
      } else {
        AppDialog.toast('停用失败: ${res['error']?['code'] ?? '未知错误'}');
      }
    } catch (e) {
      close();
      AppDialog.toast('停用失败: $e');
    }
  }

  Future<void> _uninstallPackage(Map pkg) async {
    final confirmed = await AppDialog.dangerConfirm(
      title: '卸载套件',
      message: '确认要卸载「${pkg['dname']}」？',
      confirmText: '卸载',
    );
    if (!confirmed) return;
    final close = AppDialog.showLoading(label: '卸载中...');
    try {
      final res = await DsmApi().uninstallPackageTask(pkg['id']);
      close();
      if (res['success'] == true) {
        AppDialog.toast('卸载成功');
        pkg['installed'] = false;
        pkg['launched'] = false;
        pkg['can_update'] = false;
        await _getInstalledPackages();
      } else {
        AppDialog.toast('卸载失败，错误代码: ${res['error']?['code'] ?? '未知'}');
      }
    } catch (e) {
      close();
      AppDialog.toast('卸载失败: $e');
    }
  }

  /// 安装：先选卷，再创建安装任务并轮询进度
  Future<void> _installPackage(Map pkg) async {
    if (_volumes.isEmpty) await _getVolumes();
    if (_volumes.isEmpty) {
      AppDialog.toast('未获取到存储卷信息');
      return;
    }
    final path = await _selectVolume();
    if (path == null) return;
    await _startInstallTask(pkg, path);
  }

  /// 更新：先查依赖队列，有被停用套件时确认
  Future<void> _updatePackage(Map pkg, bool isBeta) async {
    final installedPath = pkg['additional']?['installed_info']?['path']?.toString() ?? '';
    final installPath = installedPath.split('/@appstore')[0];
    setState(() => _taskText[pkg['id'].toString()] = '请稍后');
    try {
      final res = await DsmApi()
          .installPackageQueue(pkg['id'], pkg['version'].toString(), beta: isBeta);
      if (res['success'] == true) {
        final paused = res['data']?['paused_pkgs'] ?? [];
        if (paused is List && paused.isNotEmpty) {
          final cause = (res['data']?['cause_pausing_pkgs'] as List? ?? []).join(',');
          setState(() => _taskText.remove(pkg['id'].toString()));
          final confirmed = await AppDialog.dangerConfirm(
            title: '确认更新',
            message: '更新$cause时，${paused.join('，')}将被停用。',
            confirmText: '继续更新',
          );
          if (!confirmed) return;
        }
        await _startInstallTask(pkg, installPath);
      } else {
        setState(() => _taskText.remove(pkg['id'].toString()));
        AppDialog.toast('更新失败: ${res['error']?['code'] ?? '未知错误'}');
      }
    } catch (e) {
      setState(() => _taskText.remove(pkg['id'].toString()));
      AppDialog.toast('更新失败: $e');
    }
  }

  Future<void> _startInstallTask(Map pkg, String path) async {
    final id = pkg['id'].toString();
    setState(() => _taskText[id] = '准备安装…');
    try {
      final res = await DsmApi().installPackageTask(id, path);
      if (res['success'] == true) {
        AppDialog.toast('已开始安装');
        final taskId = res['data']?['taskid']?.toString() ?? '';
        _installTimers[id]?.cancel();
        _installTimers[id] = Timer.periodic(const Duration(seconds: 5), (timer) async {
          try {
            final status = await DsmApi().installPackageStatus(taskId);
            if (!mounted) {
              timer.cancel();
              return;
            }
            final data = status['data'] ?? {};
            setState(() {
              if (data['finished'] == true) {
                timer.cancel();
                _installTimers.remove(id);
                _taskText.remove(id);
                AppDialog.toast('「${pkg['dname']}」安装完成');
                _getInstalledPackages();
              } else if (data['progress'] != null) {
                final progress = data['progress'] is double
                    ? data['progress'] as double
                    : double.tryParse(data['progress'].toString()) ?? 0;
                _taskText[id] = '下载中 ${progress.toStringAsFixed(1)}%';
              } else if (data['status'] == 'installing') {
                _taskText[id] = '安装中…';
              } else if (data['status'] == 'upgrading') {
                _taskText[id] = '更新中…';
              }
            });
          } catch (_) {}
        });
      } else if (res['error']?['code'] == 4501) {
        setState(() => _taskText.remove(id));
        AppDialog.toast('此套件需配置信息，当前暂不支持，请在 WEB 端安装');
      } else {
        setState(() => _taskText.remove(id));
        AppDialog.toast('安装套件失败，代码 ${res['error']?['code'] ?? '未知'}');
      }
    } catch (e) {
      setState(() => _taskText.remove(id));
      AppDialog.toast('安装失败: $e');
    }
  }

  /// 选择安装位置
  Future<String?> _selectVolume() async {
    return await showModalBottomSheet<String>(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16.aw),
              child: Text('选择套件安装位置',
                  style: TextStyle(fontSize: 16.asp, fontWeight: FontWeight.w600)),
            ),
            ..._volumes.map((volume) {
              final sizeFree = int.tryParse(volume['size_free_byte']?.toString() ?? '') ?? 0;
              return ListTile(
                leading: const Icon(Icons.storage),
                title: Text(
                    '${volume['display_name']}（可用 ${DsmApi.formatSize(sizeFree)}B）- ${volume['fs_type']}'),
                subtitle: Text(volume['description']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, volume['volume_path']?.toString()),
              );
            }),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loadingAll = true;
      _loadingInstalled = true;
      _loadingOthers = true;
      _error = null;
    });
    await _getData();
  }

  // ==================== 搜索 ====================

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _keyword = '';
        _searchController.clear();
      }
    });
  }

  bool _matchKeyword(Map pkg) {
    final kw = _keyword.toLowerCase();
    final fields = [pkg['dname'], pkg['id'], pkg['desc'], pkg['maintainer']];
    return fields.any((f) => f != null && f.toString().toLowerCase().contains(kw));
  }

  /// 按关键字过滤套件列表（关键字为空时原样返回）
  List _filtered(List packages) =>
      _keyword.isEmpty ? packages : packages.where((p) => _matchKeyword(p)).toList();

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBeta = _betas.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索套件名称 / 描述',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _keyword = v.trim()),
              )
            : const Text('套件中心'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: '已安装'),
            const Tab(text: '全部套件'),
            const Tab(text: '社群'),
            if (hasBeta) const Tab(text: 'Beta'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          if (!_searching)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll),
        ],
      ),
      body: _error != null
          ? _buildErrorView(theme)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildInstalledTab(theme),
                _buildPackageListTab(theme, _packages, _loadingAll, '暂无可用套件'),
                _buildPackageListTab(theme, _others, _loadingOthers, '暂无社群套件'),
                if (hasBeta) _buildPackageListTab(theme, _betas, false, '暂无 Beta 套件', isBeta: true),
              ],
            ),
    );
  }

  Widget _buildErrorView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48.r, color: theme.colorScheme.error),
          12.hGap,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.aw),
            child: Text(_error ?? '', style: TextStyle(fontSize: 14.asp), textAlign: TextAlign.center),
          ),
          12.hGap,
          FilledButton(onPressed: _refreshAll, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildInstalledTab(ThemeData theme) {
    if (_loadingInstalled) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_installedPackages.isEmpty) {
      return _buildEmptyView('暂无已安装套件');
    }
    final canUpdate = _filtered(_canUpdatePackages);
    final installed = _filtered(
        _installedPackages.where((pkg) => pkg['can_update'] != true).toList());
    if (canUpdate.isEmpty && installed.isEmpty) {
      return _buildEmptyView('未找到「$_keyword」相关套件');
    }
    return RefreshIndicator(
      onRefresh: _getInstalledPackages,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 12.h),
        children: [
          if (canUpdate.isNotEmpty) ...[
            _buildSectionTitle(theme, '可更新（${canUpdate.length}）'),
            ...canUpdate.map((pkg) => _buildPackageItem(theme, pkg, true)),
            12.hGap,
            _buildSectionTitle(theme, '已安装'),
          ],
          ...installed.map((pkg) => _buildPackageItem(theme, pkg, true)),
        ],
      ),
    );
  }

  Widget _buildPackageListTab(ThemeData theme, List packages, bool loading, String emptyText,
      {bool isBeta = false}) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (packages.isEmpty) {
      return _buildEmptyView(emptyText);
    }
    final list = _filtered(packages);
    if (list.isEmpty) {
      return _buildEmptyView('未找到「$_keyword」相关套件');
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 12.h),
        itemCount: list.length,
        itemBuilder: (_, i) => _buildPackageItem(theme, list[i], false, isBeta: isBeta),
      ),
    );
  }

  Widget _buildEmptyView(String text) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Text(text, style: TextStyle(fontSize: 15.asp, color: Colors.grey)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: EdgeInsets.only(left: 4.aw, bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(fontSize: 13.asp, fontWeight: FontWeight.w600, color: theme.hintColor),
      ),
    );
  }

  /// 套件缩略图（真实图标，加载失败回退到默认图标）
  Widget _buildThumbnail(Map pkg) {
    String url = '';
    final thumbs = pkg['thumbnail'];
    if (thumbs is List && thumbs.isNotEmpty) {
      url = thumbs.last.toString();
      if (url.isNotEmpty && !url.startsWith('http')) {
        url = DsmApi().baseUrl + url;
      }
    }
    final fallback = Container(
      width: 44.aw,
      height: 44.aw,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Icon(Icons.apps, size: 26.aw, color: Colors.grey),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10.r),
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: {'Cookie': DsmApi().cookie},
        width: 44.aw,
        height: 44.aw,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _buildPackageItem(ThemeData theme, Map pkg, bool installed, {bool isBeta = false}) {
    final isBetaPkg = isBeta || pkg['additional']?['beta'] == true;
    final categoryNames = _getCategoryName(pkg['category']);
    final subtitle = installed && pkg['additional']?['updated_at'] != null
        ? pkg['additional']['updated_at'].toString()
        : categoryNames.isNotEmpty
            ? categoryNames.join('，')
            : (pkg['maintainer']?.toString() ?? '');
    final status = pkg['additional']?['status']?.toString() ?? '';

    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: pkg['installed'] == true ? () => _uninstallPackage(pkg) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.aw, vertical: 12.h),
          child: Row(
            children: [
              _buildThumbnail(pkg),
              12.wGap,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pkg['dname']?.toString() ?? pkg['id']?.toString() ?? '未知',
                            style: TextStyle(fontSize: 15.asp, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isBetaPkg) ...[
                          6.wGap,
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.aw, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text('Beta',
                                style: TextStyle(fontSize: 10.asp, color: Colors.lightBlueAccent)),
                          ),
                        ],
                        if (installed && status.isNotEmpty) ...[
                          6.wGap,
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.aw, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: (status == 'running' ? Colors.green : Colors.grey)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              status == 'running' ? '运行中' : '已停用',
                              style: TextStyle(
                                fontSize: 10.asp,
                                color: status == 'running' ? Colors.green : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    4.hGap,
                    Text(
                      installed
                          ? '${pkg['installed_version']}${pkg['can_update'] == true ? ' → ${pkg['version']}' : ''}'
                          : pkg['version']?.toString() ?? '',
                      style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              8.wGap,
              _buildActionButton(theme, pkg, isBeta: isBetaPkg),
            ],
          ),
        ),
      ),
    );
  }

  /// 操作按钮六态：获取中 / 更新 / 停用 / 启动 / 已安装 / 安装
  Widget _buildActionButton(ThemeData theme, Map pkg, {bool isBeta = false}) {
    final id = pkg['id']?.toString() ?? '';
    final taskText = _taskText[id];
    if (taskText != null) {
      return OutlinedButton(onPressed: null, child: Text(taskText, style: TextStyle(fontSize: 12.asp)));
    }
    if (pkg['can_update'] == null || pkg['installed'] == null) {
      return const OutlinedButton(onPressed: null, child: Text('获取中'));
    }
    if (pkg['can_update'] == true) {
      return FilledButton(
        onPressed: () => _updatePackage(pkg, isBeta),
        child: const Text('更新'),
      );
    }
    if (pkg['installed'] == true) {
      final startable = pkg['additional']?['startable'] == true;
      if (pkg['launched'] == true && startable) {
        return OutlinedButton(
          onPressed: () => _stopPackage(pkg),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('停用'),
        );
      }
      if (startable) {
        return OutlinedButton(
          onPressed: () => _startPackage(pkg),
          child: const Text('启动'),
        );
      }
      return const OutlinedButton(onPressed: null, child: Text('已安装'));
    }
    return OutlinedButton(
      onPressed: () => _installPackage(pkg),
      child: const Text('安装'),
    );
  }
}
