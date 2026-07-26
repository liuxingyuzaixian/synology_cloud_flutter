import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';

// 共享链接管理
class ShareManagerPage extends StatefulWidget {
  const ShareManagerPage();
  @override
  State<ShareManagerPage> createState() => ShareManagerPageState();
}

class ShareManagerPageState extends State<ShareManagerPage> {
  List _links = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await DsmApi().listShare();
    if (res['success'] == true) {
      _links = (res['data']?['links'] as List?) ?? [];
    }
    if (mounted) setState(() { _loading = false; _selected.clear(); _selectMode = false; });
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(index);
        _selectMode = true;
      }
    });
  }

  void _exitSelect() => setState(() { _selected.clear(); _selectMode = false; });

  Future<void> _copySingle(int index) async {
    final link = _links[index] as Map<String, dynamic>;
    final name = (link['path'] ?? '').toString().split('/').last;
    final url = link['url']?.toString() ?? '';
    await Clipboard.setData(ClipboardData(text: '$name: $url'));
    if (mounted) AppDialog.toast('已复制');
  }

  Future<void> _copySelected() async {
    final sb = StringBuffer();
    for (final i in _selected) {
      final link = _links[i] as Map<String, dynamic>;
      final name = (link['path'] ?? '').toString().split('/').last;
      final url = link['url']?.toString() ?? '';
      sb.writeln('$name: $url');
    }
    await Clipboard.setData(ClipboardData(text: sb.toString().trim()));
    if (mounted) { AppDialog.toast('已复制 ${_selected.length} 个'); _exitSelect(); }
  }

  Future<void> _deleteSelected() async {
    final confirm = await AppDialog.confirm(
      title: '删除共享链接',
      message: '确定要删除选中的 ${_selected.length} 个共享链接吗？',
      confirmText: '删除',
    );
    if (confirm != true) return;
    final ids = _selected.map((i) => (_links[i] as Map)['id']?.toString()).where((id) => id != null && id.isNotEmpty).cast<String>().toList();
    if (ids.isEmpty) { AppDialog.toast('无法获取链接ID'); return; }
    final close = AppDialog.showLoading(label: '删除中...');
    try {
      await DsmApi().deleteShare(ids);
      close();
      AppDialog.toast('已删除 ${ids.length} 个');
    } catch (e) {
      close();
      AppDialog.toast('删除失败: $e');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) _exitSelect();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selected.length} 项' : '共享链接管理'),
        leading: _selectMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelect)
            : null,
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: '批量复制',
              onPressed: _selected.isNotEmpty ? _copySelected : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '批量删除',
              onPressed: _selected.isNotEmpty ? _deleteSelected : null,
            ),
          ] else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_off, size: 48, color: Colors.grey[400]),
                      SizedBox(height: 12),
                      Text('暂无共享链接', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _links.length,
                  itemBuilder: (_, i) {
                    final link = _links[i] as Map<String, dynamic>;
                    final name = (link['path'] ?? '').toString().split('/').last;
                    final url = link['url']?.toString() ?? '';
                    final isSelected = _selected.contains(i);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: InkWell(
                        onTap: _selectMode ? () => _toggleSelect(i) : () => _copySingle(i),
                        onLongPress: () => _toggleSelect(i),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: _selectMode
                              ? Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey)
                              : Icon(Icons.link, color: Colors.blue[400]),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.blue)),
                          trailing: _selectMode
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () => _copySingle(i),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                                      onPressed: () async {
                                        final confirm = await AppDialog.confirm(title: '删除共享链接', message: '确定要删除此链接吗？');
                                        if (confirm == true) _load();
                                      },
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
                ),
    ) // close Scaffold
    ); // close PopScope
  }
}
