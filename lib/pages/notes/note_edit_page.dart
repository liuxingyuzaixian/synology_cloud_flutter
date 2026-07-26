import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../components/app_dialog.dart';
import '../../utils/app_adaptive.dart';
import 'note_list_page.dart';
import 'note_store.dart';

/// 笔记编辑页：新建/编辑共用，返回时自动保存，全空则丢弃。
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, this.note});

  /// 为空表示新建。
  final Note? note;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final Note _note;
  final NoteStore _store = NoteStore();

  bool _isNew = false;

  /// 本页是否产生过数据变更（供列表页决定是否刷新）。
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.note == null;
    _note = widget.note ?? Note.create();
    _titleController = TextEditingController(text: _note.title);
    _contentController = TextEditingController(text: _note.content);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _titleController.text != _note.title ||
      _contentController.text != _note.content;

  /// 返回时自动保存：全空丢弃（新建不留空笔记，编辑清空视为删除）。
  Future<void> _saveOnExit() async {
    final title = _titleController.text;
    final content = _contentController.text;
    final empty = title.trim().isEmpty && content.trim().isEmpty;

    if (empty) {
      if (!_isNew) {
        await _store.remove(_note.id);
        _changed = true;
      }
      return;
    }
    if (!_dirty && !_isNew) return;

    _note
      ..title = title
      ..content = content
      ..updatedAt = DateTime.now();
    await _store.upsert(_note);
    _changed = true;
  }

  Future<void> _delete() async {
    final ok = await AppDialog.dangerConfirm(
      title: '删除笔记',
      message: '删除后无法恢复，确定删除这条笔记吗？',
      confirmText: '删除',
    );
    if (!ok) return;
    if (!_isNew) await _store.remove(_note.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _togglePin() async {
    setState(() => _note.pinned = !_note.pinned);
    if (!_isNew) {
      await _store.upsert(_note);
      _changed = true;
    }
    AppDialog.toast(_note.pinned ? '已置顶' : '已取消置顶');
  }

  Future<void> _changeColor(int index) async {
    setState(() => _note.colorIndex = index);
    if (!_isNew) {
      await _store.upsert(_note);
      _changed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.scaffoldBackgroundColor
        : kNoteColors[_note.colorIndex % kNoteColors.length];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        await _saveOnExit();
        if (mounted) navigator.pop(_changed);
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(_isNew ? '新建笔记' : '编辑笔记'),
          actions: [
            IconButton(
              icon: Icon(
                _note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _note.pinned ? Colors.orange : null,
              ),
              tooltip: '置顶',
              onPressed: _togglePin,
            ),
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: _delete,
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 16.aw),
                children: [
                  TextField(
                    controller: _titleController,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 18.asp,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: '标题（选填）',
                      border: InputBorder.none,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '最后编辑 ${_formatTime(_note.updatedAt)}',
                        style: TextStyle(
                            fontSize: 12.asp, color: theme.hintColor),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: _contentController,
                    maxLines: null,
                    minLines: 12,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(fontSize: 15.asp, height: 1.6),
                    decoration: const InputDecoration(
                      hintText: '记点什么吧…',
                      border: InputBorder.none,
                    ),
                  ),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
            _buildColorBar(theme, isDark),
          ],
        ),
      ),
    );
  }

  /// 底部颜色选择条：6 个圆点切换卡片底色。
  Widget _buildColorBar(ThemeData theme, bool isDark) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < kNoteColors.length; i++)
              GestureDetector(
                onTap: () => _changeColor(i),
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 6.aw),
                  width: 28.aw,
                  height: 28.aw,
                  decoration: BoxDecoration(
                    color: kNoteColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _note.colorIndex == i
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                      width: _note.colorIndex == i ? 2.5 : 1,
                    ),
                  ),
                  child: _note.colorIndex == i
                      ? Icon(Icons.check,
                          size: 16.aw, color: theme.colorScheme.primary)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}/${two(time.month)}/${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
