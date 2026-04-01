class ChatMessageModel {
  ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  bool get isAgent => role == 'assistant';
  bool get isUser => role == 'user';

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static List<ChatMessageModel> listFromJson(dynamic data) {
    if (data is List) {
      return data.map((item) => ChatMessageModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}

