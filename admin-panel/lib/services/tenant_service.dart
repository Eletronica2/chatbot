import 'dart:developer';

import '../models/tenant_settings.dart';
import 'api_client.dart';

class TenantService {
  TenantService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

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
      tenantName: 'Tenant Demo',
      aiEnabled: true,
      flowEditingEnabled: true,
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
      tenantName: 'Tenant Demo',
      aiEnabled: enabled,
      flowEditingEnabled: true,
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
