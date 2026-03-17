class TenantSettings {
  TenantSettings({
    required this.tenantId,
    required this.tenantName,
    required this.aiEnabled,
    required this.flowEditingEnabled,
    required this.geminiModel,
    required this.fallbackModels,
    required this.availableModels,
  });

  final String tenantId;
  final String tenantName;
  final bool aiEnabled;
  final bool flowEditingEnabled;
  final String geminiModel;
  final List<String> fallbackModels;
  final List<String> availableModels;

  factory TenantSettings.fromJson(Map<String, dynamic> json) {
    final fallbackModels = (json['fallback_models'] is List)
        ? (json['fallback_models'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final availableModels = (json['available_models'] is List)
        ? (json['available_models'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return TenantSettings(
      tenantId: json['tenant_id']?.toString() ?? '',
      tenantName: json['tenant_name']?.toString() ?? 'Tenant',
      aiEnabled: json['ai_enabled'] == true,
      flowEditingEnabled: json['flow_editing_enabled'] != false,
      geminiModel: json['gemini_model']?.toString() ?? 'gemini-1.5-flash-latest',
      fallbackModels: fallbackModels,
      availableModels: availableModels,
    );
  }

  TenantSettings copyWith({
    bool? aiEnabled,
    bool? flowEditingEnabled,
    String? geminiModel,
    List<String>? fallbackModels,
    List<String>? availableModels,
  }) {
    return TenantSettings(
      tenantId: tenantId,
      tenantName: tenantName,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      flowEditingEnabled: flowEditingEnabled ?? this.flowEditingEnabled,
      geminiModel: geminiModel ?? this.geminiModel,
      fallbackModels: fallbackModels ?? this.fallbackModels,
      availableModels: availableModels ?? this.availableModels,
    );
  }
}
