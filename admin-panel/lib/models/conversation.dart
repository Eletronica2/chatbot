import 'package:intl/intl.dart';

class Conversation {
  Conversation({
    required this.id,
    required this.tenantId,
    required this.phoneNumber,
    required this.lastMessage,
    required this.updatedAt,
    required this.unreadCount,
    required this.aiEnabled,
    this.humanHandoffPending = false,
  });

  final String id;
  final String tenantId;
  final String phoneNumber;
  final String lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final bool aiEnabled;
  final bool humanHandoffPending;

  String get formattedUpdatedAt => DateFormat('dd/MM HH:mm').format(updatedAt);

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      lastMessage: json['last_message']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
      unreadCount: json['unread_count'] is int ? json['unread_count'] as int : int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      aiEnabled: json['ai_enabled'] == true,
      humanHandoffPending: json['human_handoff_pending'] == true,
    );
  }

  static List<Conversation> listFromJson(dynamic data) {
    if (data is List) {
      return data.map((item) => Conversation.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}

