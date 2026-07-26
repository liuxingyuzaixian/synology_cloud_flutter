import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';

/// 单条笔记模型：纯本地数据，卸载 App 即丢失。
class Note {
  Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.colorIndex = 0,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String title;
  String content;

  /// 卡片底色索引（0-5，对应列表页色板）。
  int colorIndex;
  bool pinned;
  final DateTime createdAt;
  DateTime updatedAt;

  factory Note.create() {
    final now = DateTime.now();
    return Note(
      id: now.millisecondsSinceEpoch.toString(),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Note(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'colorIndex': colorIndex,
        'pinned': pinned,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;
}

/// 笔记存储单例：内存列表 + notes.json 原子持久化。
class NoteStore {
  NoteStore._();

  factory NoteStore() => _instance;

  static final NoteStore _instance = NoteStore._();

  final List<Note> _notes = [];
  bool _loaded = false;

  /// 置顶优先，其余按更新时间倒序。
  List<Note> get sorted {
    final list = List<Note>.from(_notes);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final noteDir = Directory('${dir.path}/notes');
    if (!await noteDir.exists()) {
      await noteDir.create(recursive: true);
    }
    return File('${noteDir.path}/notes.json');
  }

  /// 首次读盘，损坏或不存在时容错为空列表。
  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List;
        _notes
          ..clear()
          ..addAll(list
              .whereType<Map>()
              .map((e) => Note.fromJson(Map<String, dynamic>.from(e))));
      }
    } catch (e) {
      AppLogger.w('NoteStore', '读取笔记失败: $e');
      _notes.clear();
    }
    _loaded = true;
  }

  /// 原子写：先写 tmp 再 rename，避免中途崩溃损坏数据。
  Future<void> _persist() async {
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(_notes.map((e) => e.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (e) {
      AppLogger.w('NoteStore', '保存笔记失败: $e');
    }
  }

  Future<void> upsert(Note note) async {
    final index = _notes.indexWhere((e) => e.id == note.id);
    if (index >= 0) {
      _notes[index] = note;
    } else {
      _notes.add(note);
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    _notes.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> togglePin(String id) async {
    final index = _notes.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _notes[index].pinned = !_notes[index].pinned;
    await _persist();
  }
}
