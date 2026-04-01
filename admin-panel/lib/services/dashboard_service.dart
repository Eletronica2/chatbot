import '../models/dashboard_overview.dart';
import 'api_client.dart';

class DashboardService {
  DashboardService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<DashboardOverviewModel> fetchOverview() async {
    final data = await _apiClient.get('/api/v1/dashboard/overview');
    return DashboardOverviewModel.fromJson(data as Map<String, dynamic>);
  }
}

final dashboardService = DashboardService(apiClient: apiClient);

