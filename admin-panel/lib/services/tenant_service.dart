import 'dart:developer';

import '../models/tenant_settings.dart';
import 'api_client.dart';

class TenantService {
  TenantService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;
  static const List<String> _defaultFallbackModels = <String>[
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.0-pro',
    'gemini-pro',
    'gemini-1.5-pro',
    'gemini-2.0-pro',
    'gemini-2.0-flash-lite',
    'gemini-1.5-flash-latest',
    'gemini-1.5-pro-latest',
  ];

  Future<TenantSettings> fetchTenantSettings(String tenantId) async {
    try {
      final data = await _apiClient.get('/api/v1/tenants/$tenantId/settings');
      if (data is Map<String, dynamic>) {
        return TenantSettings.fromJson(data);
      }
    } catch (err) {
      log('fetchTenantSettings fallback: $err');
    }
    return TenantSettings(
      tenantId: tenantId,
      tenantName: 'Cliente demo',
      aiEnabled: true,
      flowEditingEnabled: true,
      debugMode: false,
      geminiModel: 'gemini-1.5-flash-latest',
      fallbackModels: List<String>.from(_defaultFallbackModels),
      availableModels: List<String>.from(_defaultFallbackModels),
    );
  }

  Future<TenantSettings> toggleAi(String tenantId, bool enabled) async {
    try {
      final data = await _apiClient.patch(
        '/api/v1/tenants/$tenantId/settings',
        body: {'ai_enabled': enabled},
      );
      if (data is Map<String, dynamic>) {
        return TenantSettings.fromJson(data);
      }
    } catch (err) {
      log('toggleAi fallback: $err');
    }
    return TenantSettings(
      tenantId: tenantId,
      tenantName: 'Cliente demo',
      aiEnabled: enabled,
      flowEditingEnabled: true,
      debugMode: false,
      geminiModel: 'gemini-1.5-flash-latest',
      fallbackModels: List<String>.from(_defaultFallbackModels),
      availableModels: List<String>.from(_defaultFallbackModels),
    );
  }

  Future<TenantSettings> updateAiModels({
    required String tenantId,
    required String geminiModel,
    required List<String> fallbackModels,
    bool? debugMode,
  }) async {
    try {
      final data = await _apiClient.patch(
        '/api/v1/tenants/$tenantId/settings',
        body: {
          'gemini_model': geminiModel,
          'fallback_models': fallbackModels,
          if (debugMode != null) 'debug_mode': debugMode,
        },
      );
      if (data is Map<String, dynamic>) {
        return TenantSettings.fromJson(data);
      }
    } catch (err) {
      log('updateAiModels fallback: $err');
    }
    final available = <String>{geminiModel, ..._defaultFallbackModels, ...fallbackModels}.toList();
    return TenantSettings(
      tenantId: tenantId,
      tenantName: 'Cliente demo',
      aiEnabled: true,
      flowEditingEnabled: true,
      debugMode: debugMode ?? false,
      geminiModel: geminiModel,
      fallbackModels: List<String>.from(fallbackModels),
      availableModels: available,
    );
  }

  Future<bool> updateFlowMessage({
    required String tenantId,
    required String state,
    required String newMessage,
  }) async {
    try {
      await _apiClient.patch(
        '/api/v1/tenants/$tenantId/flows/$state',
        body: {'message': newMessage},
      );
      return true;
    } catch (err) {
      log('updateFlowMessage fallback: $err');
      return false;
    }
  }
}

final tenantService = TenantService(apiClient: apiClient);

