import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../models/webview_entry.dart';

/// 添加/编辑 WebView 入口
class AddWebViewPage extends StatefulWidget {
  final WebViewEntry? entry; // 编辑模式传入
  final List<WebViewEntry>? existingEntries; // 用于重复检测

  const AddWebViewPage({super.key, this.entry, this.existingEntries});

  @override
  State<AddWebViewPage> createState() => _AddWebViewPageState();
}

class _AddWebViewPageState extends State<AddWebViewPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late bool _openAsTab;
  late bool _hideUrl;

  bool get _isEdit => widget.entry != null;

  /// Whether the URL field should be disabled (built-in + hideUrl)
  bool get _urlLocked =>
      _isEdit &&
      _hideUrl &&
      (widget.entry?.id.startsWith('builtin_') ?? false);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _urlController = TextEditingController(text: widget.entry?.url ?? '');
    _openAsTab = widget.entry?.openAsTab ?? true;
    _hideUrl = widget.entry?.hideUrl ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();

    if (title.isEmpty) {
      AppDialog.toast('请输入标题');
      return;
    }
    if (url.isEmpty) {
      AppDialog.toast('请输入网址');
      return;
    }
    // 自动补全协议
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'http://$url';
    }

    // 重复检测
    if (_isDuplicate(title, finalUrl, widget.entry?.id)) {
      return;
    }

    final entry = WebViewEntry(
      id: widget.entry?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      url: finalUrl,
      openAsTab: _openAsTab,
      order: widget.entry?.order ?? 0,
      hideUrl: _hideUrl,
    );

    Navigator.pop(context, entry);
  }

  /// Check for duplicate title or URL in existing entries
  bool _isDuplicate(String title, String url, String? excludeId) {
    final entries = widget.existingEntries ?? [];
    for (final e in entries) {
      if (e.id == excludeId) continue;
      if (e.title == title) {
        AppDialog.toast('已存在同名页面「$title」，请修改标题或去管理页面编辑');
        return true;
      }
      if (e.url == url) {
        AppDialog.toast('已存在相同地址的页面「${e.title}」，请修改地址或去管理页面编辑');
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑页面' : '添加页面'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(20.w),
        children: [
          // 常用模板 (仅新建模式显示)
          if (!_isEdit) ...[
            _buildLabel('常用模板'),
            SizedBox(height: 4.h),
            Text('点击快捷添加', style: TextStyle(fontSize: 12.sp, color: theme.hintColor)),
            SizedBox(height: 8.h),
            _buildTemplateGrid(theme),
            SizedBox(height: 20.h),
            Row(
              children: [
                Expanded(child: Divider(color: theme.dividerColor)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Text('或手动添加', style: TextStyle(fontSize: 12.sp, color: theme.hintColor)),
                ),
                Expanded(child: Divider(color: theme.dividerColor)),
              ],
            ),
            SizedBox(height: 20.h),
          ],

          // 标题
          _buildLabel('标题'),
          SizedBox(height: 8.h),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: '例如：DSM 管理、路由器、监控',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: 20.h),

          // 网址
          _buildLabel('网址'),
          SizedBox(height: 8.h),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            readOnly: _urlLocked,
            style: _urlLocked ? TextStyle(color: theme.disabledColor) : null,
            decoration: InputDecoration(
              hintText: _urlLocked ? '***' : '例如：http://192.168.1.1:5000  或  BASE_URL/path',
              filled: true,
              fillColor: _urlLocked
                  ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.1)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _urlLocked
                  ? const Icon(Icons.lock_outline, size: 18)
                  : null,
            ),
          ),
          if (_urlLocked) ...[
            SizedBox(height: 4.h),
            Text(
              '该地址为内置配置，不可修改',
              style: TextStyle(fontSize: 11.sp, color: theme.hintColor),
            ),
          ],
          SizedBox(height: 12.h),

          // 隐藏网址
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('隐藏网址'),
            subtitle: const Text('不在界面中显示和复制链接'),
            value: _hideUrl,
            onChanged: _urlLocked ? null : (v) => setState(() => _hideUrl = v),
          ),
          SizedBox(height: 24.h),

          // 打开方式
          _buildLabel('打开方式'),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildOptionCard(
                  icon: Icons.tab,
                  label: 'Tab 打开',
                  description: '在底部导航栏新增标签页',
                  selected: _openAsTab,
                  onTap: () => setState(() => _openAsTab = true),
                  theme: theme,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildOptionCard(
                  icon: Icons.open_in_new,
                  label: '页面打开',
                  description: '在首页"我的应用"中显示',
                  selected: !_openAsTab,
                  onTap: () => setState(() => _openAsTab = false),
                  theme: theme,
                ),
              ),
            ],
          ),
          SizedBox(height: 32.h),

          // 预览提示
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    _openAsTab
                        ? '保存后将在底部导航栏出现新的标签页，可直接切换访问。'
                        : '保存后可在首页"我的应用"中点击打开。',
                    style: TextStyle(fontSize: 13.sp, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 常用模板列表
  static final _templates = [
    {'title': 'music-dl', 'url': 'http://zhanglei.nasfuns.fun:7022/music/local_music_page', 'icon': Icons.music_note, 'hideUrl': true},
    {'title': 'omni视频', 'url': 'http://zhanglei.nasfuns.fun:7023', 'icon': Icons.video_library, 'hideUrl': true},
    {'title': '群晖主页', 'url': 'http://BASE_URL:5000', 'icon': Icons.dns},
    {'title': '群晖音乐', 'url': 'http://BASE_URL:5000/?launchApp=SYNO.SDS.AudioStation.Application', 'icon': Icons.library_music},
    {'title': '群晖emby', 'url': 'http://BASE_URL:8096', 'icon': Icons.movie},
    {'title': 'NoteStation', 'url': 'http://BASE_URL:5000/?launchApp=SYNO.SDS.NoteStation.Application', 'icon': Icons.note},
    {'title': 'FileStation', 'url': 'http://BASE_URL:5000/?launchApp=SYNO.SDS.App.FileStation3.Instance', 'icon': Icons.folder},
  ];

  /// Quick add with duplicate check and tab/page prompt
  Future<void> _quickAdd(Map<String, dynamic> tpl) async {
    final host = DsmApi().server?.host ?? '';
    final rawUrl = tpl['url'] as String;
    final resolvedUrl = rawUrl.replaceFirst('BASE_URL', host);
    final title = tpl['title'] as String;

    // Duplicate check
    if (_isDuplicate(title, resolvedUrl, null)) return;

    // Prompt: add as tab or page?
    final asTab = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加「$title」'),
        content: const Text('选择打开方式'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('添加为页面'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加到 Tab'),
          ),
        ],
      ),
    );
    if (asTab == null) return; // cancelled

    final entry = WebViewEntry(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      url: resolvedUrl,
      openAsTab: asTab,
      hideUrl: tpl['hideUrl'] == true,
    );
    Navigator.pop(context, entry);
  }

  Widget _buildTemplateGrid(ThemeData theme) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: _templates.map((tpl) {
        return ActionChip(
          avatar: Icon(tpl['icon'] as IconData, size: 18, color: theme.colorScheme.primary),
          label: Text(tpl['title'] as String, style: TextStyle(fontSize: 13.sp)),
          backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.2),
          side: BorderSide.none,
          onPressed: () => _quickAdd(tpl),
        );
      }).toList(),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String label,
    required String description,
    required bool selected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: theme.colorScheme.primary.withOpacity(0.5))
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? theme.colorScheme.primary : theme.hintColor,
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              description,
              style: TextStyle(fontSize: 11.sp, color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
