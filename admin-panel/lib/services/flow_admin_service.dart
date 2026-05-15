import 'package:flutter/foundation.dart';
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
    this.detectedIntent,
    this.confidence,
    this.metadata = const {},
  });

  final String userMessage;
  final String botResponse;
  final String? flowUsed;
  final String? state;
  final String? detectedIntent;
  final double? confidence;
  final Map<String, dynamic> metadata;

  factory SimulationSendResult.fromJson(Map<String, dynamic> json) {
    final metadata = Map<String, dynamic>.from(json['metadata'] ?? {});
    final botResponse = json['bot_response']?.toString() ?? '';
    return SimulationSendResult(
      userMessage: json['user_message']?.toString() ?? '',
      botResponse: botResponse,
      flowUsed: json['flow_used']?.toString(),
      state: json['state']?.toString(),
      detectedIntent: json['detected_intent']?.toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      metadata: metadata,
    );
  }

  /// Texto final para exibir no simulador (usa flow_state_message se a API truncar).
  String get displayResponse {
    final flowMsg = metadata['flow_state_message']?.toString().trim() ?? '';
    if (flowMsg.isEmpty) return botResponse;
    if (_flowContentIncluded(botResponse, flowMsg)) return botResponse;
    final intro = _extractIntro(botResponse, flowMsg);
    if (intro.isNotEmpty) return '$intro\n\n$flowMsg';
    return flowMsg;
  }

  bool _flowContentIncluded(String reply, String flowMsg) {
    final anchors = <String>[];
    for (final line in flowMsg.split('\n')) {
      final cleaned = line.replaceAll(RegExp(r'[*_~`]'), '').trim();
      if (cleaned.length >= 12) anchors.add(cleaned.substring(0, cleaned.length.clamp(0, 40)).toLowerCase());
    }
    if (anchors.isEmpty) return reply.length >= flowMsg.length * 0.85;
    final lower = reply.toLowerCase();
    final hits = anchors.where((a) => lower.contains(a)).length;
    return hits >= (anchors.length >= 2 ? 2 : 1);
  }

  String _extractIntro(String reply, String flowMsg) {
    var intro = reply.trim();
    intro = intro.replaceAll(RegExp(r'\*+\s*$'), '').trim();

    final flowLines = flowMsg
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[*_~`]'), '').trim().toLowerCase())
        .where((l) => l.length > 10)
        .toList();

    final kept = <String>[];
    for (final line in intro.split('\n')) {
      final plain = line.replaceAll(RegExp(r'[*_~`]'), '').trim().toLowerCase();
      if (plain.isEmpty || plain.length <= 2) continue;
      if (flowLines.any((fl) => plain.contains(fl) || fl.startsWith(plain.substring(0, plain.length.clamp(0, 30))))) {
        break;
      }
      if (plain.endsWith(':') && !plain.contains(RegExp(r'\d'))) continue;
      kept.add(line.trimRight());
    }
    if (kept.isNotEmpty) return kept.join('\n');
    final first = intro.split('\n').first.trim();
    return first;
  }
}

class FlowAdminService {
  FlowAdminService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  // Corrigido: prefixo /api/v1/flows
  Future<List<FlowSummaryModel>> listFlows() async {
    final data = await _apiClient.get('/api/v1/flows');
    if (data is List) {
      return data.map((e) => FlowSummaryModel.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  Future<String> getFlowYaml(String name) async {
    final data = await _apiClient.get('/api/v1/flows/$name');
    if (data is Map<String, dynamic>) {
      return data['yaml_content']?.toString() ?? '';
    }
    return '';
  }

  Future<void> saveFlowYaml({
    required String flowName,
    required String yamlContent,
  }) async {
    await _apiClient.put(
      '/api/v1/flows/$flowName',
      body: {'yaml_content': yamlContent},
    );
  }

  Future<void> reloadFlows() async {
    await _apiClient.post('/api/v1/flows/reload');
  }

  Future<SimulationSendResult> sendSimulationMessage({
    required String tenantId,
    required String message,
    String? phoneNumber,
    String? flowName,
  }) async {
    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'message': message,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phone_number'] = phoneNumber.trim();
    }
    if (flowName != null && flowName.trim().isNotEmpty) {
      payload['flow_name'] = flowName.trim();
    }

    debugPrint('FLOW_ADMIN_SERVICE: Sending POST to /api/v1/simulation/send with payload: $payload');
    // Corrigido: prefixo /api/v1/simulation/send
    final data = await _apiClient.post('/api/v1/simulation/send', body: payload);
    debugPrint('FLOW_ADMIN_SERVICE: Received response: $data');
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
