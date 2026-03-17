import 'dart:developer';

import 'api_client.dart';

class FlowSummaryModel {
  FlowSummaryModel({
    required this.name,
    this.description,
    this.startState,
  });

  final String name;
  final String? description;
  final String? startState;

  factory FlowSummaryModel.fromJson(Map<String, dynamic> json) {
    return FlowSummaryModel(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      startState: json['start_state']?.toString(),
    );
  }
}

class FlowAdminService {
  FlowAdminService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<FlowSummaryModel>> listFlows() async {
    final data = await _apiClient.get('/api/v1/flows');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(FlowSummaryModel.fromJson)
          .toList();
    }
    return [];
  }

  Future<String> getFlowYaml(String flowName) async {
    final data = await _apiClient.get('/api/v1/flows/$flowName');
    if (data is Map<String, dynamic>) {
      return data['yaml_content']?.toString() ?? '';
    }
    return '';
  }

  Future<void> saveFlowYaml({required String flowName, required String yamlContent}) async {
    await _apiClient.put('/api/v1/flows/$flowName', body: {'yaml_content': yamlContent});
  }

  Future<void> reloadFlows() async {
    try {
      await _apiClient.post('/api/v1/flows/reload');
    } catch (err) {
      log('reloadFlows warning: $err');
    }
  }
}

final flowAdminService = FlowAdminService(apiClient: apiClient);
