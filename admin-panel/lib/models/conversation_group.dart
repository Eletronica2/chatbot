class ConversationGroup {
  ConversationGroup({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
    this.isDefault = false,
    this.memberUserIds = const <String>[],
    this.memberCount = 0,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? description;
  final bool isDefault;
  final List<String> memberUserIds;
  final int memberCount;

  factory ConversationGroup.fromJson(Map<String, dynamic> json) {
    final members = <String>[];
    final rawMembers = json['member_user_ids'] ?? json['members'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map) {
          final id = item['user_id']?.toString() ?? item['id']?.toString();
          if (id != null && id.isNotEmpty) members.add(id);
        } else {
          final id = item?.toString() ?? '';
          if (id.isNotEmpty) members.add(id);
        }
      }
    }
    final count = int.tryParse(json['member_count']?.toString() ?? '') ??
        members.length;
    return ConversationGroup(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      isDefault: json['is_default'] == true || json['is_default'] == 1,
      memberUserIds: members,
      memberCount: count,
    );
  }

  static List<ConversationGroup> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => ConversationGroup.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    if (data is Map && data['items'] is List) {
      return listFromJson(data['items']);
    }
    return const <ConversationGroup>[];
  }
}
