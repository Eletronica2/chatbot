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
    this.assignmentMode = 'ai',
    this.assignedUserId,
    this.assignedUserName,
    this.groupId,
    this.groupName,
  });

  final String id;
  final String tenantId;
  final String phoneNumber;
  final String lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final bool aiEnabled;
  final bool humanHandoffPending;

  /// `ai` | `human`
  final String assignmentMode;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? groupId;
  final String? groupName;

  String get formattedUpdatedAt => DateFormat('dd/MM HH:mm').format(updatedAt);

  bool get isAssignedToAi =>
      assignmentMode.toLowerCase() == 'ai' ||
      (assignedUserId == null || assignedUserId!.isEmpty);

  String get assigneeLabel {
    if (isAssignedToAi) return 'IA';
    final name = assignedUserName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return assignedUserId ?? 'Humano';
  }

  Conversation copyWith({
    String? assignmentMode,
    String? assignedUserId,
    String? assignedUserName,
    String? groupId,
    String? groupName,
    bool? aiEnabled,
    bool? humanHandoffPending,
    int? unreadCount,
    String? lastMessage,
  }) {
    return Conversation(
      id: id,
      tenantId: tenantId,
      phoneNumber: phoneNumber,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      humanHandoffPending: humanHandoffPending ?? this.humanHandoffPending,
      assignmentMode: assignmentMode ?? this.assignmentMode,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      assignedUserName: assignedUserName ?? this.assignedUserName,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final handoff = json['human_handoff_pending'] == true;
    final modeRaw = json['assignment_mode']?.toString().trim().toLowerCase();
    final mode = (modeRaw == null || modeRaw.isEmpty)
        ? (handoff ? 'human' : 'ai')
        : modeRaw;
    return Conversation(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      lastMessage: json['last_message']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      unreadCount: json['unread_count'] is int
          ? json['unread_count'] as int
          : int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      aiEnabled: json['ai_enabled'] == true ||
          (json['ai_enabled'] == null && mode == 'ai' && !handoff),
      humanHandoffPending: handoff,
      assignmentMode: mode,
      assignedUserId: json['assigned_user_id']?.toString(),
      assignedUserName: json['assigned_user_name']?.toString() ??
          json['assigned_user_display_name']?.toString(),
      groupId: json['group_id']?.toString(),
      groupName: json['group_name']?.toString(),
    );
  }

  static List<Conversation> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}
