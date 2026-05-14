import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';

enum ActionType {
  sendImage,
  sendLink,
  httpRequest,
  delay,
  sendDocument;

  String get apiValue => switch (this) {
        ActionType.sendImage => 'send_image',
        ActionType.sendLink => 'send_link',
        ActionType.httpRequest => 'http_request',
        ActionType.delay => 'delay',
        ActionType.sendDocument => 'send_document',
      };

  String get label => switch (this) {
        ActionType.sendImage => 'Enviar imagem',
        ActionType.sendLink => 'Enviar link',
        ActionType.httpRequest => 'Requisição HTTP',
        ActionType.delay => 'Aguardar',
        ActionType.sendDocument => 'Enviar documento',
      };

  static ActionType fromApi(String value) => switch (value) {
        'send_image' => ActionType.sendImage,
        'send_link' => ActionType.sendLink,
        'http_request' => ActionType.httpRequest,
        'delay' => ActionType.delay,
        'send_document' => ActionType.sendDocument,
        _ => ActionType.httpRequest,
      };
}

class FlowAction {
  const FlowAction({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.actionType,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int tenantId;
  final String name;
  final ActionType actionType;
  final Map<String, dynamic> config;
  final String createdAt;
  final String updatedAt;

  factory FlowAction.fromJson(Map<String, dynamic> json) => FlowAction(
        id: (json['id'] as num).toInt(),
        tenantId: (json['tenant_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        actionType: ActionType.fromApi(json['action_type'] as String? ?? ''),
        config: (json['config'] as Map<String, dynamic>?) ?? {},
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ActionsService {
  const ActionsService();

  Future<List<FlowAction>> listActions() async {
    final data = await apiClient.get('/api/v1/actions') as List<dynamic>;
    return data
        .map((e) => FlowAction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FlowAction> createAction({
    required String name,
    required ActionType actionType,
    required Map<String, dynamic> config,
  }) async {
    final data = await apiClient.post(
      '/api/v1/actions',
      body: {
        'name': name,
        'action_type': actionType.apiValue,
        'config': config,
      },
    ) as Map<String, dynamic>;
    return FlowAction.fromJson(data);
  }

  Future<FlowAction> updateAction({
    required int id,
    String? name,
    Map<String, dynamic>? config,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (config != null) body['config'] = config;
    final data = await apiClient.patch(
      '/api/v1/actions/$id',
      body: body,
    ) as Map<String, dynamic>;
    return FlowAction.fromJson(data);
  }

  Future<void> deleteAction(int id) async {
    await apiClient.delete('/api/v1/actions/$id');
  }

  /// Convert raw bytes + mime to base64 for the config payload.
  static String bytesToBase64(Uint8List bytes) => base64Encode(bytes);
}

final actionsService = ActionsService();
