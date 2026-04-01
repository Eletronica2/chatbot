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

class SimulationSendResult {
  SimulationSendResult({
    required this.userMessage,
    required this.botResponse,
    this.flowUsed,
    this.state,
    this.source,
    this.detectedIntent,
    this.confidence,
  });

  final String userMessage;
  final String botResponse;
  final String? flowUsed;
  final String? state;
  final String? source;
  final String? detectedIntent;
  final double? confidence;

  factory SimulationSendResult.fromJson(Map<String, dynamic> json) {
    final confidenceRaw = json['confidence'];
    double? confidence;
    if (confidenceRaw is num) {
      confidence = confidenceRaw.toDouble();
    } else if (confidenceRaw is String) {
      confidence = double.tryParse(confidenceRaw);
    }

    return SimulationSendResult(
      userMessage: json['user_message']?.toString() ?? '',
      botResponse: json['bot_response']?.toString() ?? '',
      flowUsed: json['flow_used']?.toString(),
      state: json['state']?.toString(),
      source: json['source']?.toString(),
      detectedIntent: json['detected_intent']?.toString(),
      confidence: confidence,
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

  Future<SimulationSendResult> sendSimulationMessage({
    required String tenantId,
    required String message,
    String? phoneNumber,
  }) async {
    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'message': message,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phone_number'] = phoneNumber.trim();
    }

    final data = await _apiClient.post('/simulation/send', body: payload);
    if (data is Map<String, dynamic>) {
      return SimulationSendResult.fromJson(data);
    }
    return SimulationSendResult(
      userMessage: message,
      botResponse: 'Não foi possível simular no momento.',
    );
  }
}

final flowAdminService = FlowAdminService(apiClient: apiClient);

