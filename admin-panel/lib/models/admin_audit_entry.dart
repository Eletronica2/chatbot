class AdminAuditEntryModel {
  AdminAuditEntryModel({
    required this.auditId,
    required this.tenantId,
    required this.action,
    required this.entityType,
    required this.entityKey,
    required this.summary,
    this.actorUserId,
    this.actorEmail,
    this.metadata,
    this.createdAt,
  });

  final String auditId;
  final String tenantId;
  final String? actorUserId;
  final String? actorEmail;
  final String action;
  final String entityType;
  final String entityKey;
  final String summary;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  factory AdminAuditEntryModel.fromJson(Map<String, dynamic> json) {
    return AdminAuditEntryModel(
      auditId: json['audit_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      actorUserId: json['actor_user_id']?.toString(),
      actorEmail: json['actor_email']?.toString(),
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityKey: json['entity_key']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      metadata: (json['metadata'] is Map<String, dynamic>)
          ? json['metadata'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
