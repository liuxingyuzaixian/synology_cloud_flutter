import 'dart:convert';

/// WebView 入口配置
class WebViewEntry {
  final String id;
  final String title;
  final String url;
  final bool openAsTab; // true=底部Tab, false=首页内打开
  final int order;
  final bool hideUrl; // true=隐藏网址显示和复制

  const WebViewEntry({
    required this.id,
    required this.title,
    required this.url,
    this.openAsTab = true,
    this.order = 0,
    this.hideUrl = false,
  });

  WebViewEntry copyWith({
    String? id,
    String? title,
    String? url,
    bool? openAsTab,
    int? order,
    bool? hideUrl,
  }) {
    return WebViewEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      openAsTab: openAsTab ?? this.openAsTab,
      order: order ?? this.order,
      hideUrl: hideUrl ?? this.hideUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'openAsTab': openAsTab,
        'order': order,
        'hideUrl': hideUrl,
      };

  factory WebViewEntry.fromJson(Map<String, dynamic> json) => WebViewEntry(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        openAsTab: json['openAsTab'] ?? true,
        order: json['order'] ?? 0,
        hideUrl: json['hideUrl'] ?? false,
      );

  static List<WebViewEntry> listFromStorage(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List;
      return list.map((e) => WebViewEntry.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<WebViewEntry> entries) {
    return jsonEncode(entries.map((e) => e.toJson()).toList());
  }
}
