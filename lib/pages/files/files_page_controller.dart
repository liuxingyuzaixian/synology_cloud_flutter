import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../network/dsm_api.dart';
import '../../../models/file_model.dart';

class FilesPageController extends ChangeNotifier {
  // State
  String _currentPath = '/';
  List<FileModel> _files = [];
  bool _loading = true;
  String? _error;
  bool _isGridView = false;
  String _sortBy = 'name';
  String _sortDirection = 'asc';
  bool _isSearching = false;
  String _searchQuery = '';

  // Cancel token for API requests
  CancelToken? _cancelToken;

  // Getters
  String get currentPath => _currentPath;
  List<FileModel> get files => _files;
  bool get loading => _loading;
  String? get error => _error;
  bool get isGridView => _isGridView;
  String get sortBy => _sortBy;
  String get sortDirection => _sortDirection;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;

  // Setters with notifyListeners
  set isGridView(bool value) {
    _isGridView = value;
    notifyListeners();
  }

  set sortBy(String value) {
    if (_sortBy == value) {
      // Toggle direction if same field
      _sortDirection = _sortDirection == 'asc' ? 'desc' : 'asc';
    } else {
      _sortBy = value;
      _sortDirection = 'asc';
    }
    _loadFiles();
  }

  set searchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void toggleSortDirection() {
    _sortDirection = _sortDirection == 'asc' ? 'desc' : 'asc';
    _loadFiles();
  }

  void toggleSearch() {
    _isSearching = !_isSearching;
    if (!_isSearching) _searchQuery = '';
    notifyListeners();
  }

  /// Filtered files based on search query
  List<FileModel> get displayFiles {
    if (_searchQuery.isEmpty) return _files;
    final q = _searchQuery.toLowerCase();
    return _files.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  /// Breadcrumb segments: list of (label, path)
  List<(String, String)> get breadcrumbSegments {
    final segments = <(String, String)>[];
    segments.add(('根目录', '/'));

    if (_currentPath != '/') {
      final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
      var accumulated = '';
      for (final part in parts) {
        accumulated += '/$part';
        segments.add((part, accumulated));
      }
    }
    return segments;
  }

  /// Initialize: load root files
  Future<void> init() async {
    await _loadFiles();
  }

  /// Navigate to a directory
  Future<void> navigateTo(String path) async {
    _currentPath = path;
    await _loadFiles();
  }

  /// Go up one level
  Future<void> goUp() async {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      _currentPath = '/';
    } else {
      parts.removeLast();
      _currentPath = parts.isEmpty ? '/' : '/${parts.join('/')}';
    }
    await _loadFiles();
  }

  /// Refresh current directory
  Future<void> refresh() async {
    await _loadFiles();
  }

  /// Load files from DSM API
  Future<void> _loadFiles() async {
    _cancelToken?.cancel('new request');
    _cancelToken = CancelToken();

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      Map res;
      if (_currentPath == '/') {
        res = await DsmApi().shareList(cancelToken: _cancelToken);
      } else {
        res = await DsmApi().fileList(
          _currentPath,
          sortBy: _sortBy,
          sortDirection: _sortDirection,
        );
      }

      if (res['success'] == false) {
        _error = res['error']?['code']?.toString() ?? '加载失败';
        _files = [];
      } else {
        final dataKey = _currentPath == '/' ? 'shares' : 'files';
        final list = res['data']?[dataKey] as List? ?? [];
        _files = list
            .map((e) => FileModel.fromJson(e as Map<String, dynamic>))
            .toList();

        // Sort client-side for share list (API doesn't support custom sorting)
        if (_currentPath == '/') {
          _sortFiles();
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      _error = e.message ?? '网络错误';
      _files = [];
    } catch (e) {
      _error = e.toString();
      _files = [];
    }

    _loading = false;
    notifyListeners();
  }

  /// Client-side sort for share list
  void _sortFiles() {
    _files.sort((a, b) {
      // Folders first
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;

      int cmp;
      switch (_sortBy) {
        case 'size':
          cmp = a.size.compareTo(b.size);
          break;
        case 'time':
          cmp = a.mtime.compareTo(b.mtime);
          break;
        default:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortDirection == 'asc' ? cmp : -cmp;
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel('disposed');
    super.dispose();
  }
}
