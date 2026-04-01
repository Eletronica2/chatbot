import '../models/tenant_user.dart';
import 'api_client.dart';

class TenantUserService {
  TenantUserService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<TenantUserModel>> listUsers(String tenantId) async {
    final data = await _apiClient.get('/api/v1/tenants/$tenantId/users');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(TenantUserModel.fromJson)
          .toList();
    }
    return <TenantUserModel>[];
  }

  Future<TenantUserActionTokenModel> inviteUser({
    required String tenantId,
    required String email,
    required String displayName,
    required String role,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/users/invite',
      body: {
        'email': email,
        'display_name': displayName,
        'role': role,
      },
    );
    return TenantUserActionTokenModel.fromJson(data as Map<String, dynamic>);
  }

  Future<TenantUserModel> updateUser({
    required String tenantId,
    required String userId,
    String? displayName,
    String? role,
    String? status,
  }) async {
    final data = await _apiClient.patch(
      '/api/v1/tenants/$tenantId/users/$userId',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (role != null) 'role': role,
        if (status != null) 'status': status,
      },
    );
    return TenantUserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<TenantUserActionTokenModel> createPasswordReset({
    required String tenantId,
    required String userId,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/users/$userId/reset-password',
    );
    return TenantUserActionTokenModel.fromJson(data as Map<String, dynamic>);
  }
}

final tenantUserService = TenantUserService(apiClient: apiClient);
