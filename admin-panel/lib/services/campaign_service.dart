import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/campaign.dart';
import 'api_client.dart';

class CampaignService {
  CampaignService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<CampaignSendReadinessModel> getSendReadiness(String tenantId) async {
    final data = await _apiClient.get('/api/v1/tenants/$tenantId/campaigns/send-readiness');
    return CampaignSendReadinessModel.fromJson(data as Map<String, dynamic>);
  }

  Future<CampaignDetailModel> getCampaignDetail({
    required String tenantId,
    required String campaignId,
  }) async {
    final data = await _apiClient.get('/api/v1/tenants/$tenantId/campaigns/$campaignId');
    return CampaignDetailModel.fromJson(data as Map<String, dynamic>);
  }

  Future<List<CampaignSummaryModel>> listCampaigns(String tenantId) async {
    try {
      final data = await _apiClient.get('/api/v1/tenants/$tenantId/campaigns');
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(CampaignSummaryModel.fromJson)
            .toList();
      }
    } catch (err) {
      log('listCampaigns: $err');
    }
    return [];
  }

  Future<CampaignSummaryModel> createCampaign({
    required String tenantId,
    required String name,
    required String templateName,
    String templateLanguage = 'pt_BR',
    String? accountKey,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/campaigns',
      body: {
        'name': name,
        'template_name': templateName,
        'template_language': templateLanguage,
        if (accountKey != null) 'account_key': accountKey,
      },
    );
    return CampaignSummaryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<Uint8List> downloadImportTemplate({
    required String tenantId,
    required String campaignId,
  }) async {
    final response = await _apiClient.getRaw(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/import-template.xlsx',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw ApiException(response.body, statusCode: response.statusCode);
  }

  Future<CampaignValidationModel> validateUpload({
    required String tenantId,
    required String campaignId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final response = await _apiClient.postMultipart(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/validate',
      fields: const {},
      files: [
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      ],
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      return CampaignValidationModel.fromJson(data as Map<String, dynamic>);
    }
    throw ApiException(response.body, statusCode: response.statusCode);
  }

  Future<CampaignSummaryModel> startCampaign({
    required String tenantId,
    required String campaignId,
    bool confirm = true,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/start',
      body: {'confirm': confirm},
    );
    return CampaignSummaryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<CampaignSummaryModel> pauseCampaign({
    required String tenantId,
    required String campaignId,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/pause',
      body: {},
    );
    return CampaignSummaryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<Uint8List> downloadResults({
    required String tenantId,
    required String campaignId,
  }) async {
    final response = await _apiClient.getRaw(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/results.xlsx',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw ApiException(response.body, statusCode: response.statusCode);
  }

  Future<CampaignSummaryModel> cancelCampaign({
    required String tenantId,
    required String campaignId,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/campaigns/$campaignId/cancel',
      body: {},
    );
    return CampaignSummaryModel.fromJson(data as Map<String, dynamic>);
  }
}

final campaignService = CampaignService(apiClient: apiClient);