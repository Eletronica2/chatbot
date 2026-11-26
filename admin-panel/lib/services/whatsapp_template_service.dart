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
    String? footerText,
    Map<String, dynamic>? header,
    List<Map<String, dynamic>>? buttons,
    List<String>? bodyExamples,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-templates',
      body: {
        'name': name,
        'language': language,
        'category': category,
        'body_text': bodyText,
        if (accountKey != null) 'account_key': accountKey,
        if (footerText != null && footerText.isNotEmpty) 'footer_text': footerText,
        if (header != null) 'header': header,
        if (buttons != null && buttons.isNotEmpty) 'buttons': buttons,
        if (bodyExamples != null && bodyExamples.isNotEmpty) 'body_examples': bodyExamples,
      },
    );
    return WhatsAppTemplateModel.fromJson(data as Map<String, dynamic>);
  }

  Future<List<TemplateStatusWatchItem>> watchTemplateStatus({
    required String tenantId,
    required String accountKey,
    int sinceUnix = 0,
  }) async {
    try {
      final data = await _apiClient.get(
        '/api/v1/tenants/$tenantId/whatsapp-templates/status-watch'
        '?account_key=$accountKey&since=$sinceUnix',
      );
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(TemplateStatusWatchItem.fromJson)
            .toList();
      }
    } catch (err) {
      log('watchTemplateStatus error: $err');
    }
    return <TemplateStatusWatchItem>[];
  }

  Future<Map<String, dynamic>> sendTemplate({
    required String tenantId,
    required String templateName,
    required String language,
    String? accountKey,
    String? to,
    List<String>? bodyParameters,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-templates/send',
      body: {
        'template_name': templateName,
        'language': language,
        if (accountKey != null) 'account_key': accountKey,
        if (to != null && to.isNotEmpty) 'to': to,
        if (bodyParameters != null && bodyParameters.isNotEmpty)
          'body_parameters': bodyParameters,
      },
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }
}

class TemplateStatusWatchItem {
  const TemplateStatusWatchItem({
    this.templateId,
    required this.name,
    required this.language,
    required this.status,
    this.rejectedReason,
    this.updatedAt = 0,
  });

  final String? templateId;
  final String name;
  final String language;
  final String status;
  final String? rejectedReason;
  final int updatedAt;

  factory TemplateStatusWatchItem.fromJson(Map<String, dynamic> json) {
    return TemplateStatusWatchItem(
      templateId: json['template_id'] as String?,
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      rejectedReason: json['rejected_reason'] as String?,
      updatedAt: json['updated_at'] is int
          ? json['updated_at'] as int
          : int.tryParse('${json['updated_at']}') ?? 0,
    );
  }
}

final whatsAppTemplateService = WhatsAppTemplateService(apiClient: apiClient);
