import 'dart:developer';

import '../models/whatsapp_account.dart';
import 'api_client.dart';

class WhatsAppAccountService {
  WhatsAppAccountService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<WhatsAppAccountModel>> listAccounts(String tenantId) async {
    try {
      final data = await _apiClient.get('/api/v1/tenants/$tenantId/whatsapp-accounts');
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(WhatsAppAccountModel.fromJson)
            .toList();
      }
    } catch (err) {
      log('listAccounts fallback: $err');
    }
    return <WhatsAppAccountModel>[];
  }

  Future<WhatsAppAccountModel> createAccount({
    required String tenantId,
    required String accountKey,
    required String displayName,
    required String phoneNumberId,
    required String displayPhoneNumber,
    required String accessToken,
    required String verifyToken,
    required String status,
    required bool isDefault,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-accounts',
      body: {
        'account_key': accountKey,
        'display_name': displayName,
        'phone_number_id': phoneNumberId,
        'display_phone_number': displayPhoneNumber,
        'access_token': accessToken,
        'verify_token': verifyToken,
        'status': status,
        'is_default': isDefault,
      },
    );
    return WhatsAppAccountModel.fromJson(data as Map<String, dynamic>);
  }

  Future<WhatsAppAccountModel> updateAccount({
    required String tenantId,
    required String accountKey,
    String? displayName,
    String? phoneNumberId,
    String? displayPhoneNumber,
    String? accessToken,
    String? verifyToken,
    String? status,
    bool? isDefault,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (phoneNumberId != null) 'phone_number_id': phoneNumberId,
      if (displayPhoneNumber != null) 'display_phone_number': displayPhoneNumber,
      if (accessToken != null) 'access_token': accessToken,
      if (verifyToken != null) 'verify_token': verifyToken,
      if (status != null) 'status': status,
      if (isDefault != null) 'is_default': isDefault,
    };
    final data = await _apiClient.patch(
      '/api/v1/tenants/$tenantId/whatsapp-accounts/$accountKey',
      body: body,
    );
    return WhatsAppAccountModel.fromJson(data as Map<String, dynamic>);
  }
}

final whatsAppAccountService = WhatsAppAccountService(apiClient: apiClient);
