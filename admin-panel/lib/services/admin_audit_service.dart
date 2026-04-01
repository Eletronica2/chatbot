import '../models/admin_audit_entry.dart';
import 'api_client.dart';

class AdminAuditService {
  AdminAuditService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<AdminAuditEntryModel>> listAuditLogs() async {
    final data = await _apiClient.get('/api/v1/admin/audit-logs');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(AdminAuditEntryModel.fromJson)
          .toList();
    }
    return <AdminAuditEntryModel>[];
  }
}

final adminAuditService = AdminAuditService(apiClient: apiClient);
