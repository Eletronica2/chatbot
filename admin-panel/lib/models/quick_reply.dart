class QuickReply {
  QuickReply({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.title,
    required this.shortcut,
    required this.content,
  });

  final String id;
  final String tenantId;
  final String userId;
  final String title;
  final String shortcut;
  final String content;

  /// Normalized shortcut without leading `/`.
  String get bareShortcut {
    final raw = shortcut.trim();
    if (raw.startsWith('/')) return raw.substring(1);
    return raw;
  }

  factory QuickReply.fromJson(Map<String, dynamic> json) {
    return QuickReply(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      shortcut: json['shortcut']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
    );
  }

  static List<QuickReply> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => QuickReply.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    if (data is Map && data['items'] is List) {
      return listFromJson(data['items']);
    }
    return const <QuickReply>[];
  }
}
