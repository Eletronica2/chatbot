class ChatMessageModel {
  ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.messageType = 'text',
    this.mediaUrl,
    this.mediaMimeType,
    this.filename,
    this.deliveryFailed = false,
    this.deliveryErrorHint,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final String messageType;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? filename;
  final bool deliveryFailed;
  final String? deliveryErrorHint;

  bool get isAgent => role == 'assistant';
  bool get isUser => role == 'user';
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      messageType: json['message_type']?.toString() ?? 'text',
      mediaUrl: json['media_url']?.toString(),
      mediaMimeType: json['media_mime_type']?.toString(),
      filename: json['filename']?.toString(),
      deliveryFailed: json['delivery_failed'] == true,
      deliveryErrorHint: json['delivery_error_hint']?.toString(),
    );
  }

  static List<ChatMessageModel> listFromJson(dynamic data) {
    if (data is List) {
      return data.map((item) => ChatMessageModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}