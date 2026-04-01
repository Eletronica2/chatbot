import 'dart:developer';

import '../models/tenant_admin.dart';
import 'api_client.dart';

class AdminTenantService {
  AdminTenantService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<TenantAdminSummary>> listTenants() async {
    final data = await _apiClient.get('/api/v1/admin/tenants');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(TenantAdminSummary.fromJson)
          .toList();
    }
    return <TenantAdminSummary>[];
  }

  Future<TenantAdminSummary> getTenant(String tenantId) async {
    final data = await _apiClient.get('/api/v1/admin/tenants/$tenantId');
    return TenantAdminSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<TenantAdminSummary> createTenant({
    required String tenantId,
    required String name,
    required String email,
    required String ownerName,
    required String ownerEmail,
    required String ownerPassword,
    required String plan,
    int? monthlyMessageLimit,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/admin/tenants',
      body: {
        'tenant_id': tenantId,
        'name': name,
        'email': email,
        'owner_name': ownerName,
        'owner_email': ownerEmail,
        'owner_password': ownerPassword,
        'plan': plan,
        if (monthlyMessageLimit != null) 'monthly_message_limit': monthlyMessageLimit,
      },
    );
    return TenantAdminSummary.fromJson(data as Map<String, dynamic>);
  }

  void logSelectedTenant(String tenantId) {
    log('selected tenant: $tenantId');
  }
}

final adminTenantService = AdminTenantService(apiClient: apiClient);
