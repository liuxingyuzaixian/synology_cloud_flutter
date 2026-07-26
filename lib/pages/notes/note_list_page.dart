import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/app_preferences.dart';
import 'note_edit_page.dart';
import 'note_store.dart';

/// 记事本卡片色板（浅色底，index 与 Note.colorIndex 对应）。
const List<Color> kNoteColors = [
  Color(0xFFFFFFFF), // 默认白
  Color(0xFFFFF3E0), // 杏黄
  Color(0xFFE8F5E9), // 浅绿
  Color(0xFFE3F2FD), // 浅蓝
  Color(0xFFF3E5F5), // 浅紫
  Color(0xFFFFEBEE), // 浅粉
];

/// 记事本列表页：两列卡片网格，支持搜索、置顶、删除。纯本地存储。
class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  static const String prefTipShown = 'notes_local_tip_shown';

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  final NoteStore _store = NoteStore();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _store.load();
    if (!mounted) return;
    setState(() => _loading = false);
    _showFirstTipIfNeeded();
  }

  /// 首次进入弹强提示：数据仅存本机，卸载 App 会丢失。
  void _showFirstTipIfNeeded() {
    if (AppPreferences.getBool(NoteListPage.prefTipShown)) return;
    AppPreferences.putBool(NoteListPage.prefTipShown, true);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: const Text('温馨提示'),
        content: const Text(
          '记事本数据仅保存在本机，不会上传到 NAS 或云端。\n\n'
          '卸载 App 或清除应用数据后，所有笔记将丢失，重要内容请自行备份。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  List<Note> get _visibleNotes {
    final list = _store.sorted;
    if (_keyword.isEmpty) return list;
    final kw = _keyword.toLowerCase();
    return list
        .where((e) =>
            e.title.toLowerCase().contains(kw) ||
            e.content.toLowerCase().contains(kw))
        .toList();
  }

  Future<void> _openEdit([Note? note]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoteEditPage(note: note)),
    );
    if (changed == true && mounted) setState(() {});
  }

  void _showItemMenu(Note note) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                  note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(note.pinned ? '取消置顶' : '置顶'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _store.togglePin(note.id);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await AppDialog.dangerConfirm(
                  title: '删除笔记',
                  message: '删除后无法恢复，确定删除这条笔记吗？',
                  confirmText: '删除',
                );
                if (!ok) return;
                await _store.remove(note.id);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索标题或内容',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _keyword = v.trim()),
              )
            : const Text('记事本'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                _keyword = '';
              }
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('新建笔记'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildLocalTipBar(theme),
                Expanded(child: _buildGrid(theme)),
              ],
            ),
    );
  }

  /// 常驻提示条：浅黄底提醒本地存储。
  Widget _buildLocalTipBar(ThemeData theme) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 8.h),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15.aw, color: Colors.orange),
          SizedBox(width: 6.aw),
          Expanded(
            child: Text(
              '笔记仅保存在本机，卸载 App 后会丢失',
              style: TextStyle(fontSize: 12.asp, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(ThemeData theme) {
    final notes = _visibleNotes;
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note, size: 64.aw, color: theme.hintColor),
            SizedBox(height: 12.h),
            Text(
              _keyword.isEmpty ? '还没有笔记\n点右下角开始记录' : '没有匹配的笔记',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.asp, color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12.aw, 12.h, 12.aw, 88.h),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.aw,
        mainAxisSpacing: 10.h,
        childAspectRatio: 0.82,
      ),
      itemCount: notes.length,
      itemBuilder: (_, index) => _buildCard(theme, notes[index]),
    );
  }

  Widget _buildCard(ThemeData theme, Note note) {
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : kNoteColors[note.colorIndex % kNoteColors.length];
    final title = note.title.trim();
    final content = note.content.trim();

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEdit(note),
        onLongPress: () => _showItemMenu(note),
        child: Padding(
          padding: EdgeInsets.all(12.aw),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (title.isNotEmpty)
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.asp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (note.pinned)
                    Icon(Icons.push_pin, size: 14.aw, color: Colors.orange),
                ],
              ),
              if (title.isNotEmpty) SizedBox(height: 6.h),
              Expanded(
                child: Text(
                  content.isEmpty ? '（无内容）' : content,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.asp, height: 1.4),
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                _formatTime(note.updatedAt),
                style: TextStyle(fontSize: 11.asp, color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '今天 ${two(time.hour)}:${two(time.minute)}';
    }
    if (time.year == now.year) {
      return '${time.month}月${time.day}日 ${two(time.hour)}:${two(time.minute)}';
    }
    return '${time.year}/${two(time.month)}/${two(time.day)}';
  }
}
