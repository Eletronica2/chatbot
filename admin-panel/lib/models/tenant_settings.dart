class TenantSettings {
  TenantSettings({
    required this.tenantId,
    required this.tenantName,
    required this.aiEnabled,
    required this.flowEditingEnabled,
    required this.debugMode,
    required this.geminiModel,
    required this.fallbackModels,
    required this.availableModels,
    this.aiProvider = 'gemini',
    this.localAiEnabled = false,
  });

  final String tenantId;
  final String tenantName;
  final bool aiEnabled;
  final bool flowEditingEnabled;
  final bool debugMode;
  final String geminiModel;
  final List<String> fallbackModels;
  final List<String> availableModels;
  final String aiProvider;
  final bool localAiEnabled;

  factory TenantSettings.fromJson(Map<String, dynamic> json) {
    final fallbackModels = (json['fallback_models'] is List)
        ? (json['fallback_models'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final availableModels = (json['available_models'] is List)
        ? (json['available_models'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return TenantSettings(
      tenantId: json['tenant_id']?.toString() ?? '',
      tenantName: json['tenant_name']?.toString() ?? 'Cliente',
      aiEnabled: json['ai_enabled'] == true,
      flowEditingEnabled: json['flow_editing_enabled'] != false,
      debugMode: json['debug_mode'] == true,
      geminiModel: json['gemini_model']?.toString() ?? 'gemini-1.5-flash-latest',
      fallbackModels: fallbackModels,
      availableModels: availableModels,
      aiProvider: json['ai_provider']?.toString() ?? 'gemini',
      localAiEnabled: json['local_ai_enabled'] == true,
    );
  }

  TenantSettings copyWith({
    bool? aiEnabled,
    bool? flowEditingEnabled,
    bool? debugMode,
    String? geminiModel,
    List<String>? fallbackModels,
    List<String>? availableModels,
    String? aiProvider,
    bool? localAiEnabled,
  }) {
    return TenantSettings(
      tenantId: tenantId,
      tenantName: tenantName,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      flowEditingEnabled: flowEditingEnabled ?? this.flowEditingEnabled,
      debugMode: debugMode ?? this.debugMode,
      geminiModel: geminiModel ?? this.geminiModel,
      fallbackModels: fallbackModels ?? this.fallbackModels,
      availableModels: availableModels ?? this.availableModels,
      aiProvider: aiProvider ?? this.aiProvider,
      localAiEnabled: localAiEnabled ?? this.localAiEnabled,
    );
  }
}

