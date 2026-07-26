import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synology_cloud_flutter/pages/files/favorites_page.dart';
import 'package:synology_cloud_flutter/pages/files/remote_folder_page.dart';
import 'package:synology_cloud_flutter/pages/files/share_manager_page.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../utils/app_adaptive.dart';
import '../../../models/file_model.dart';
import '../common/viewers/music_player_page.dart';
import '../common/viewers/text_reader_page.dart';
import '../common/viewers/video_player_page.dart';
import 'files_page_controller.dart';

class FilesPage extends StatefulWidget {
  final void Function(bool isAtRoot, void Function() goUp)? onPathChanged;
  final void Function(bool inSelect, void Function()? exitFn)? onSelectModeChanged;
  const FilesPage({super.key, this.onPathChanged, this.onSelectModeChanged});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final FilesPageController _ctrl;

  bool get _isAtRoot => _ctrl.currentPath == '/';

  // Multi-select
  bool _selectMode = false;
  final Set<int> _selectedIndices = {};

  void _exitSelect() => setState(() { _selectMode = false; _selectedIndices.clear(); widget.onSelectModeChanged?.call(false, null); });

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _selectMode = false;
          widget.onSelectModeChanged?.call(false, null);
        }
      } else {
        _selectedIndices.add(index);
        _selectMode = true;
        widget.onSelectModeChanged?.call(true, _exitSelect);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _ctrl = FilesPageController();
    _ctrl.addListener(_onChanged);
    _ctrl.init();
    _notifyPath();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    _notifyPath();
  }

  void _notifyPath() {
    widget.onPathChanged?.call(_isAtRoot, _ctrl.goUp);
  }

  // ==================== UI Builders ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) _exitSelect();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIndices.length} 项' : '文件'),
        leading: _selectMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelect)
            : null,
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除选中',
                  onPressed: _selectedIndices.isNotEmpty ? () => _batchDelete() : null,
                ),
              ]
            : [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, size: 20.r),
            onSelected: (v) {
              if (v == 'share_manager') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ShareManagerPage()));
              } else if (v == 'remote_folder') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteFolderPage()));
              } else if (v == 'favorites') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => FavoritesPage(
                  onPathSelected: (path) {
                    _ctrl.navigateTo(path);
                  },
                )));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'favorites', child: ListTile(
                leading: Icon(Icons.star_outline, size: 20),
                title: Text('收藏夹'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              )),
              const PopupMenuItem(value: 'share_manager', child: ListTile(
                leading: Icon(Icons.link, size: 20),
                title: Text('共享链接管理'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              )),
              const PopupMenuItem(value: 'remote_folder', child: ListTile(
                leading: Icon(Icons.cloud_upload_outlined, size: 20),
                title: Text('装载远程'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              )),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildToolbar(),
              if (_ctrl.isSearching) _buildSearchBar(),
              _buildBreadcrumb(),
              Expanded(child: _buildBody()),
            ],
          ),
          // Download progress bar with cancel X
          if (_fileDownloadProgress != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _cancelFileDownload,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _fileDownloadProgress! > 0 ? _fileDownloadProgress : null,
                      backgroundColor: Colors.transparent,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          Positioned(
            right: 16.aw,
            bottom: 16.h,
            child: FloatingActionButton(
              heroTag: 'files_fab',
              onPressed: _showFabMenu,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    ));
  }

  /// Top toolbar with view toggle, sort, search
  Widget _buildToolbar() {
    return Container(
      height: 44.h,
      padding: EdgeInsets.symmetric(horizontal: 12.aw),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Sort
          _buildSortChip(),
          const Spacer(),
          // Search toggle
          IconButton(
            icon: Icon(
              _ctrl.isSearching ? Icons.close : Icons.search,
              size: 20.r,
            ),
            onPressed: _ctrl.toggleSearch,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: 36.aw, height: 36.h),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip() {
    final labels = {'name': '名称', 'size': '大小', 'time': '时间'};
    return PopupMenuButton<String>(
      onSelected: (v) => _ctrl.sortBy = v,
      itemBuilder: (_) => labels.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Row(
                children: [
                  if (_ctrl.sortBy == e.key)
                    Icon(Icons.check, size: 16.r, color: Theme.of(context).colorScheme.primary)
                  else
                    SizedBox(width: 16.r),
                  SizedBox(width: 8.aw),
                  Text(e.value),
                  const Spacer(),
                  if (_ctrl.sortBy == e.key)
                    GestureDetector(
                      onTap: () => _ctrl.toggleSortDirection(),
                      child: Icon(
                        _ctrl.sortDirection == 'asc'
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 14.r,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(),
      child: Chip(
        label: Text(
          '排序: ${labels[_ctrl.sortBy] ?? _ctrl.sortBy}',
          style: TextStyle(fontSize: 12.asp),
        ),
        avatar: Icon(Icons.sort, size: 16.r),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(12.aw, 0, 12.aw, 8.h),
      child: TextField(
        autofocus: true,
        decoration: InputDecoration(
          hintText: '搜索当前文件夹...',
          prefixIcon: Icon(Icons.search, size: 18.r),
          suffixIcon: _ctrl.searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 18.r),
                  onPressed: () => _ctrl.searchQuery = '',
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 12.aw, vertical: 8.h),
          isDense: true,
        ),
        onChanged: (v) => _ctrl.searchQuery = v,
      ),
    );
  }

  /// Breadcrumb navigation
  Widget _buildBreadcrumb() {
    final segments = _ctrl.breadcrumbSegments;
    return Container(
      height: 36.h,
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.symmetric(horizontal: 12.aw),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        separatorBuilder: (_, __) => Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.aw),
          child: Icon(Icons.chevron_right, size: 16.r, color: Colors.grey),
        ),
        itemBuilder: (context, index) {
          final seg = segments[index];
          final isLast = index == segments.length - 1;
          return Center(
            child: GestureDetector(
              onTap: isLast ? null : () => _ctrl.navigateTo(seg.$2),
              child: Text(
                seg.$1,
                style: TextStyle(
                  fontSize: 13.asp,
                  color: isLast ? Colors.black87 : Theme.of(context).colorScheme.primary,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Main body content
  Widget _buildBody() {
    if (_ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ctrl.error != null) {
      return _buildError();
    }
    final files = _ctrl.displayFiles;
    if (files.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      onRefresh: _ctrl.refresh,
      child: _buildList(files),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48.r, color: Colors.red.shade300),
          SizedBox(height: 12.h),
          Text(_ctrl.error!, style: TextStyle(fontSize: 14.asp, color: Colors.red)),
          SizedBox(height: 16.h),
          FilledButton.tonal(
            onPressed: _ctrl.refresh,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64.r, color: Colors.grey.shade300),
          SizedBox(height: 16.h),
          Text(
            '文件夹为空',
            style: TextStyle(fontSize: 16.asp, color: Colors.grey.shade500),
          ),
          SizedBox(height: 8.h),
          Text(
            '点击右下角按钮创建文件夹或上传文件',
            style: TextStyle(fontSize: 13.asp, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ==================== List View ====================

  Widget _buildList(List<FileModel> files) {
    return ListView.builder(
      padding: EdgeInsets.only(bottom: 80.h),
      itemCount: files.length,
      itemBuilder: (context, index) => _buildListItem(files[index], index),
    );
  }

  Widget _buildListItem(FileModel file, int index) {
    final isSelected = _selectedIndices.contains(index);
    return InkWell(
      onTap: _selectMode ? () => _toggleSelect(index) : () => _onFileTap(file),
      onDoubleTap: _selectMode ? null : () => _onFileDoubleTap(file),
      onLongPress: () => _toggleSelect(index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.aw, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  size: 22,
                ),
              ),
            _buildFileIcon(file, size: 36),
            SizedBox(width: 12.aw),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedText(
                    file.name,
                    maxLines: 1,
                    style: TextStyle(fontSize: 14.asp, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '${file.sizeText}  ${file.modifiedTimeText}',
                    style: TextStyle(fontSize: 11.asp, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_horiz, size: 20.r, color: Colors.grey.shade500),
              onPressed: () => _showContextMenu(file),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a Text with search query highlighted
  Widget _highlightedText(String text, {int? maxLines, TextOverflow? overflow, TextStyle? style, TextAlign? textAlign}) {
    final query = _ctrl.searchQuery.trim();
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(text, maxLines: maxLines, overflow: overflow, style: style, textAlign: textAlign);
    }
    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + query.length);
    final after = text.substring(idx + query.length);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before, style: style),
          TextSpan(
            text: match,
            style: (style ?? const TextStyle()).copyWith(
              backgroundColor: Colors.yellow.shade200,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after, style: style),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }

  // ==================== Grid View ====================

  // Grid view removed

    Widget _buildFileIcon(FileModel file, {required double size}) {
    final r = size.r;
    if (file.isDir) {
      return Icon(Icons.folder, size: r, color: const Color(0xFF5BB8FF));
    }
    final iconData = _iconForType(file.fileType);
    final color = _colorForType(file.fileType);
    return Container(
      width: r,
      height: r,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Icon(iconData, size: r * 0.6, color: color),
    );
  }

  IconData _iconForType(FileTypeEnum type) {
    switch (type) {
      case FileTypeEnum.image:
        return Icons.image;
      case FileTypeEnum.movie:
        return Icons.movie;
      case FileTypeEnum.music:
        return Icons.music_note;
      case FileTypeEnum.word:
        return Icons.description;
      case FileTypeEnum.ppt:
        return Icons.slideshow;
      case FileTypeEnum.excel:
        return Icons.table_chart;
      case FileTypeEnum.text:
        return Icons.article;
      case FileTypeEnum.zip:
        return Icons.archive;
      case FileTypeEnum.code:
        return Icons.code;
      case FileTypeEnum.pdf:
        return Icons.picture_as_pdf;
      case FileTypeEnum.apk:
        return Icons.android;
      case FileTypeEnum.iso:
        return Icons.disc_full;
      case FileTypeEnum.folder:
        return Icons.folder;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForType(FileTypeEnum type) {
    switch (type) {
      case FileTypeEnum.image:
        return const Color(0xFF10B981);
      case FileTypeEnum.movie:
        return const Color(0xFFEF4444);
      case FileTypeEnum.music:
        return const Color(0xFFF59E0B);
      case FileTypeEnum.word:
        return const Color(0xFF3B82F6);
      case FileTypeEnum.ppt:
        return const Color(0xFFF97316);
      case FileTypeEnum.excel:
        return const Color(0xFF22C55E);
      case FileTypeEnum.text:
        return const Color(0xFF6B7280);
      case FileTypeEnum.zip:
        return const Color(0xFF8B5CF6);
      case FileTypeEnum.code:
        return const Color(0xFF06B6D4);
      case FileTypeEnum.pdf:
        return const Color(0xFFEF4444);
      case FileTypeEnum.apk:
        return const Color(0xFF84CC16);
      case FileTypeEnum.iso:
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  // ==================== Actions ====================

  Timer? _tapTimer;
  double? _fileDownloadProgress;
  CancelToken? _fileCancelToken;

  void _onFileTap(FileModel file) {
    if (file.isDir) {
      _ctrl.navigateTo(file.path);
      return;
    }
    // Single tap: delayed to detect double-tap
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 300), () {
      _openWithBuiltInViewer(file);
    });
  }

  void _onFileDoubleTap(FileModel file) {
    if (file.isDir) return;
    _tapTimer?.cancel();
    _openWithSystemDefault(file);
  }

  /// Try built-in viewer; if unsupported, fallback to system default
  void _openWithBuiltInViewer(FileModel file) {
    final type = file.fileType;
    switch (type) {
      case FileTypeEnum.music:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MusicPlayerPage(fileName: file.name, filePath: file.path),
        ));
        break;
      case FileTypeEnum.movie:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerPage(fileName: file.name, filePath: file.path),
        ));
        break;
      case FileTypeEnum.text:
      case FileTypeEnum.code:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TextReaderPage(fileName: file.name, filePath: file.path),
        ));
        break;
      default:
        // No built-in viewer → use system default (no toast)
        _openWithSystemDefault(file);
        break;
    }
  }

  /// Download to temp, then open with system default app
  Future<void> _openWithSystemDefault(FileModel file) async {
    _tapTimer?.cancel();

    // Large file prompt (>100MB)
    if (file.size > 100 * 1024 * 1024) {
      final sizeText = DsmApi.formatSize(file.size);
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('文件较大'),
          content: Text('${file.name}\n大小: $sizeText'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'copy'),
              child: const Text('复制链接'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'download'),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      if (action == 'copy') {
        final url = '${DsmApi().baseUrl}/webapi/entry.cgi'
            '?api=SYNO.FileStation.Download&method=download&version=2'
            '&path=${Uri.encodeComponent(file.path)}&mode=download'
            '&_sid=${DsmApi().sid}';
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) AppDialog.toast('链接已复制');
        return;
      }
      if (action != 'download') return;
    }

    try {
      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (dir == null) return;
      final downloadDir = Directory('${dir.path}/downloads');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final localFile = File('${downloadDir.path}/${file.name}');
      if (!await localFile.exists()) {
        _fileCancelToken = CancelToken();
        setState(() => _fileDownloadProgress = 0);
        final url = '${DsmApi().baseUrl}/webapi/entry.cgi'
            '?api=SYNO.FileStation.Download&method=download&version=2'
            '&path=${Uri.encodeComponent(file.path)}&mode=download'
            '&_sid=${DsmApi().sid}';
        await Dio().download(url, localFile.path,
            options: Options(headers: DsmApi().authHeaders),
            cancelToken: _fileCancelToken,
            onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _fileDownloadProgress = received / total);
          }
        });
        _fileCancelToken = null;
        if (mounted) setState(() => _fileDownloadProgress = null);
      }
      await OpenFilex.open(localFile.path);
    } on DioException catch (e) {
      _fileCancelToken = null;
      if (e.type == DioExceptionType.cancel) {
        // User cancelled
      } else if (mounted) {
        setState(() => _fileDownloadProgress = null);
        AppDialog.toast('打开失败');
      }
    } catch (e) {
      _fileCancelToken = null;
      if (mounted) {
        setState(() => _fileDownloadProgress = null);
        AppDialog.toast('打开失败: $e');
      }
    }
  }

  void _showFileDetail(FileModel file) {
    final sizeText = file.isDir ? '--' : DsmApi.formatSize(file.size);
    final modified = file.modifiedTimeText;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('路径', file.path),
            _detailRow('类型', file.isDir ? '文件夹' : file.fileType.name),
            _detailRow('大小', sizeText),
            _detailRow('修改时间', modified),
            if (file.realPath != null) _detailRow('实际路径', file.realPath!),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _compressFile(FileModel file) async {
    final path = file.path;
    final close = AppDialog.showLoading(label: '正在压缩...');
    try {
      final res = await DsmApi().compressTask([path], '/${path.split('/')[1]}');
      close();
      if (res['success'] == true) {
        AppDialog.toast('压缩任务已提交');
      } else {
        AppDialog.toast('压缩失败: ${res['error']?['code'] ?? ''}');
      }
    } catch (e) {
      close();
      AppDialog.toast('压缩失败: $e');
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    try {
      // Android: use external files dir (visible under Android/data/<package>/files/)
      // iOS: use application documents dir
      final dir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (dir == null) { AppDialog.toast('无法获取存储目录'); return; }
      final downloadDir = Directory('${dir.path}/downloads');
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      final localFile = File('${downloadDir.path}/${file.name}');
      _fileCancelToken = CancelToken();
      setState(() => _fileDownloadProgress = 0);
      final url = '${DsmApi().baseUrl}/webapi/entry.cgi'
          '?api=SYNO.FileStation.Download&method=download&version=2'
          '&path=${Uri.encodeComponent(file.path)}&mode=download'
          '&_sid=${DsmApi().sid}';
      await Dio().download(url, localFile.path,
          options: Options(headers: DsmApi().authHeaders),
          cancelToken: _fileCancelToken,
          onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _fileDownloadProgress = received / total);
        }
      });
      _fileCancelToken = null;
      if (mounted) {
        setState(() => _fileDownloadProgress = null);
        AppDialog.toast('下载完成: ${localFile.path}');
        // Open after download — handle APK specifically (needs install permission)
        final ext = file.name.split('.').last.toLowerCase();
        if (ext == 'apk') {
          await OpenFilex.open(localFile.path, type: 'application/vnd.android.package-archive');
        } else {
          await OpenFilex.open(localFile.path);
        }
      }
    } on DioException catch (e) {
      _fileCancelToken = null;
      if (e.type != DioExceptionType.cancel && mounted) {
        setState(() => _fileDownloadProgress = null);
        AppDialog.toast('下载失败');
      }
    }
  }

  Future<void> _createFileInFolder(FileModel folder) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入文件名（含扩展名）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    // Create an empty local temp file and upload it to the folder
    final close = AppDialog.showLoading(label: '创建中...');
    try {
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/$name');
      await tmpFile.writeAsString('');
      final token = CancelToken();
      await DsmApi().uploadFile(folder.path, tmpFile.path, token, (_, __) {});
      await tmpFile.delete();
      close();
      AppDialog.toast('文件已创建');
      _ctrl.refresh();
    } catch (e) {
      close();
      AppDialog.toast('创建失败: $e');
    }
  }

  void _cancelFileDownload() {
    _fileCancelToken?.cancel();
    _fileCancelToken = null;
    setState(() => _fileDownloadProgress = null);
  }

  void _showContextMenu(FileModel file) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(top: 8.h),
                width: 40.aw,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 12.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.aw),
                child: Row(
                  children: [
                    _buildFileIcon(file, size: 32),
                    SizedBox(width: 12.aw),
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.asp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8.h),
              const Divider(height: 1),
              _contextAction(Icons.info_outline, '详情', () => _showFileDetail(file)),
              _contextAction(Icons.edit, '重命名', () => _renameFile(file)),
              _contextAction(Icons.content_copy, '复制', () => _copyFile(file)),
              _contextAction(Icons.drive_file_move, '移动', () => _moveFile(file)),
              _contextAction(Icons.share, '分享链接', () => _shareFile(file)),
              _contextAction(Icons.compress, '压缩', () => _compressFile(file)),
              _contextAction(Icons.favorite_border, '添加收藏', () => _addFavorite(file)),
              if (!file.isDir)
                _contextAction(Icons.download, '下载', () {
                  _downloadFile(file);
                }),
              if (file.isDir)
                _contextAction(Icons.note_add_outlined, '新建文件', () {
                  Navigator.pop(context);
                  _createFileInFolder(file);
                }),
              _contextAction(Icons.delete, '删除', () => _deleteFile(file), isDestructive: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contextAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : null,
        size: 22.r,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.asp,
          color: isDestructive ? Colors.red : null,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  // ==================== File Operations ====================

  Future<void> _renameFile(FileModel file) async {
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == file.name) return;

    final close = AppDialog.showLoading(label: '重命名中...');
    try {
      final res = await DsmApi().rename(file.path, newName);
      close();
      if (res['success'] == false) {
        AppDialog.toast('重命名失败: ${res['error']?['code'] ?? '未知错误'}');
      } else {
        AppDialog.toast('重命名成功');
        _ctrl.refresh();
      }
    } catch (e) {
      close();
      AppDialog.toast('重命名失败: $e');
    }
  }

  Future<void> _deleteFile(FileModel file) async {
    final confirmed = await AppDialog.confirm(
      title: '删除确认',
      message: '确定要删除 "${file.name}" 吗？此操作不可撤销。',
      confirmText: '删除',
    );
    if (!confirmed) return;

    final close = AppDialog.showLoading(label: '删除中...');
    try {
      final res = await DsmApi().deleteTask([file.path]);
      close();
      if (res['success'] == false) {
        AppDialog.toast('删除失败: ${res['error']?['code'] ?? '未知错误'}');
      } else {
        AppDialog.toast('删除成功');
        _ctrl.refresh();
      }
    } catch (e) {
      close();
      AppDialog.toast('删除失败: $e');
    }
  }

  Future<void> _batchDelete() async {
    final files = _ctrl.displayFiles;
    final selected = _selectedIndices.map((i) => files[i]).toList();
    if (selected.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      title: '批量删除',
      message: '确定要删除选中的 ${selected.length} 个文件/文件夹吗？',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final close = AppDialog.showLoading(label: '删除中...');
    var success = 0, failed = 0;
    for (final file in selected) {
      try {
        await DsmApi().deleteTask([file.path]);
        success++;
      } catch (_) { failed++; }
    }
    close();
    AppDialog.toast('删除完成：$success 成功${failed > 0 ? "，$failed 失败" : ""}');
    _exitSelect();
    _ctrl.refresh();
  }

  Future<void> _copyFile(FileModel file) async {
    final dest = await _pickFolder('选择目标文件夹');
    if (dest == null) return;

    final close = AppDialog.showLoading(label: '复制中...');
    try {
      final res = await DsmApi().copyMoveTask([file.path], dest, false);
      close();
      if (res['success'] == false) {
        AppDialog.toast('复制失败');
      } else {
        AppDialog.toast('复制成功');
        _ctrl.refresh();
      }
    } catch (e) {
      close();
      AppDialog.toast('复制失败: $e');
    }
  }

  Future<void> _moveFile(FileModel file) async {
    final dest = await _pickFolder('选择目标文件夹');
    if (dest == null) return;

    final close = AppDialog.showLoading(label: '移动中...');
    try {
      final res = await DsmApi().copyMoveTask([file.path], dest, true);
      close();
      if (res['success'] == false) {
        AppDialog.toast('移动失败');
      } else {
        AppDialog.toast('移动成功');
        _ctrl.refresh();
      }
    } catch (e) {
      close();
      AppDialog.toast('移动失败: $e');
    }
  }

  Future<void> _shareFile(FileModel file) async {
    final close = AppDialog.showLoading(label: '创建分享链接...');
    try {
      final res = await DsmApi().createShare([file.path]);
      close();
      final links = res['data']?['links'] as List?;
      if (links != null && links.isNotEmpty) {
        final url = links[0]['url'] ?? '';
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('分享链接'),
            content: SelectableText(url.toString()),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url.toString()));
                  AppDialog.toast('已复制');
                  Navigator.pop(context);
                },
                child: const Text('复制链接'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        AppDialog.toast('创建分享失败');
      }
    } catch (e) {
      close();
      AppDialog.toast('分享失败: $e');
    }
  }

  Future<void> _addFavorite(FileModel file) async {
    final close = AppDialog.showLoading();
    try {
      final res = await DsmApi().favoriteAdd(file.name, file.path);
      close();
      if (res['success'] == false) {
        AppDialog.toast('添加收藏失败');
      } else {
        AppDialog.toast('已添加收藏');
      }
    } catch (e) {
      close();
      AppDialog.toast('添加收藏失败: $e');
    }
  }

  Future<String?> _pickFolder(String title) async {
    // Simple folder picker dialog using share list
    final res = await DsmApi().shareList();
    final shares = (res['data']?['shares'] as List?) ?? [];
    if (shares.isEmpty) {
      AppDialog.toast('没有可用的共享文件夹');
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 300.h,
          child: ListView.builder(
            itemCount: shares.length,
            itemBuilder: (_, index) {
              final share = shares[index] as Map<String, dynamic>;
              final path = share['path'] ?? '';
              final name = share['name'] ?? '';
              return ListTile(
                leading: Icon(Icons.folder, color: const Color(0xFF5BB8FF), size: 24.r),
                title: Text(name, style: TextStyle(fontSize: 14.asp)),
                onTap: () => Navigator.pop(context, path),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// FAB actions
  void _showFabMenu() {
    // 根目录不支持上传操作
    final canUpload = !_isAtRoot;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12.h),
            ListTile(
              leading: Icon(Icons.create_new_folder, size: 24.r),
              title: Text('新建文件夹', style: TextStyle(fontSize: 14.asp)),
              onTap: () {
                Navigator.pop(context);
                _createFolder();
              },
            ),
            if (canUpload) ...[
              ListTile(
                leading: Icon(Icons.upload_file, size: 24.r),
                title: Text('上传文件', style: TextStyle(fontSize: 14.asp)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadFiles();
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, size: 24.r),
                title: Text('拍照上传', style: TextStyle(fontSize: 14.asp)),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoAndUpload();
                },
              ),
              ListTile(
                leading: Icon(Icons.videocam_outlined, size: 24.r),
                title: Text('录像上传', style: TextStyle(fontSize: 14.asp)),
                onTap: () {
                  Navigator.pop(context);
                  _recordVideoAndUpload();
                },
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhotoAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.camera);
    if (xFile == null) return;
    await _uploadFileToCurrentDir(xFile);
  }

  Future<void> _recordVideoAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickVideo(source: ImageSource.camera);
    if (xFile == null) return;
    await _uploadFileToCurrentDir(xFile);
  }

  Future<void> _uploadFileToCurrentDir(XFile xFile) async {
    final targetPath = _ctrl.currentPath;
    final close = AppDialog.showLoading(label: '上传中...');
    try {
      final token = CancelToken();
      await DsmApi().uploadFile(targetPath, xFile.path, token, (sent, total) {});
      close();
      AppDialog.toast('上传成功');
      _ctrl.refresh();
    } catch (e) {
      close();
      AppDialog.toast('上传失败: $e');
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final close = AppDialog.showLoading(label: '创建中...');
    try {
      final res = await DsmApi().createFolder(_ctrl.currentPath, name);
      close();
      if (res['success'] == false) {
        AppDialog.toast('创建失败: ${res['error']?['code'] ?? '未知错误'}');
      } else {
        AppDialog.toast('创建成功');
        _ctrl.refresh();
      }
    } catch (e) {
      close();
      AppDialog.toast('创建失败: $e');
    }
  }

  Future<void> _pickAndUploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;

      final targetPath = _ctrl.currentPath;
      final total = result.files.length;
      var success = 0;
      var failed = 0;

      final close = AppDialog.showLoading(label: '准备上传 $total 个文件...');
      for (var i = 0; i < total; i++) {
        final file = result.files[i];
        final filePath = file.path;
        if (filePath == null) { failed++; continue; }

        final token = CancelToken();
        try {
          await DsmApi().uploadFile(targetPath, filePath, token, (sent, totalBytes) {
            // progress callback
          });
          success++;
        } catch (e) {
          failed++;
        }
      }
      close();
      AppDialog.toast('上传完成：$success 成功${failed > 0 ? '，$failed 失败' : ''}');
      if (success > 0) _ctrl.refresh();
    } catch (e) {
      AppDialog.toast('选择文件失败: $e');
    }
  }
}
