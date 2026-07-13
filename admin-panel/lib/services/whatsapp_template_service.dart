import 'dart:developer';

import '../models/whatsapp_template.dart';
import 'api_client.dart';

class WhatsAppTemplateService {
  WhatsAppTemplateService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<WhatsAppTemplateModel>> listTemplates(
    String tenantId, {
    String? accountKey,
  }) async {
    try {
      final query = accountKey == null ? '' : '?account_key=$accountKey';
      final data = await _apiClient.get(
        '/api/v1/tenants/$tenantId/whatsapp-templates$query',
      );
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(WhatsAppTemplateModel.fromJson)
            .toList();
      }
    } catch (err) {
      log('listTemplates error: $err');
    }
    return <WhatsAppTemplateModel>[];
  }

  Future<WhatsAppTemplateModel> createTemplate({
    required String tenantId,
    required String name,
    required String language,
    required String category,
    required String bodyText,
    String? accountKey,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-templates',
      body: {
        'name': name,
        'language': language,
        'category': category,
        'body_text': bodyText,
        if (accountKey != null) 'account_key': accountKey,
      },
    );
    return WhatsAppTemplateModel.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> sendTemplate({
    required String tenantId,
    required String templateName,
    required String language,
    String? accountKey,
    String? to,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-templates/send',
      body: {
        'template_name': templateName,
        'language': language,
        if (accountKey != null) 'account_key': accountKey,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }
}

final whatsAppTemplateService = WhatsAppTemplateService(apiClient: apiClient);
