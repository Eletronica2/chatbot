class TenantSettings {
  TenantSettings({
    required this.tenantId,
    required this.tenantName,
    required this.aiEnabled,
    required this.flowEditingEnabled,
  });

  final String tenantId;
  final String tenantName;
  final bool aiEnabled;
  final bool flowEditingEnabled;

  factory TenantSettings.fromJson(Map<String, dynamic> json) {
    return TenantSettings(
      tenantId: json['tenant_id']?.toString() ?? '',
      tenantName: json['tenant_name']?.toString() ?? 'Tenant',
      aiEnabled: json['ai_enabled'] == true,
      flowEditingEnabled: json['flow_editing_enabled'] != false,
    );
  }

  TenantSettings copyWith({bool? aiEnabled, bool? flowEditingEnabled}) {
    return TenantSettings(
      tenantId: tenantId,
      tenantName: tenantName,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      flowEditingEnabled: flowEditingEnabled ?? this.flowEditingEnabled,
    );
  }
}
