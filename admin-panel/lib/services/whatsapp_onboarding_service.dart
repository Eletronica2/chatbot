import 'api_client.dart';

class WhatsAppOnboardingService {
  WhatsAppOnboardingService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getEmbeddedSignupConfig({String? tenantId}) async {
    final query = (tenantId != null && tenantId.isNotEmpty)
        ? '?tenant_id=${Uri.encodeQueryComponent(tenantId)}'
        : '';
    final data = await _apiClient.get('/api/v1/meta/embedded-signup/config$query');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getEmbeddedSignupPreflight() async {
    final data = await _apiClient.get('/api/v1/meta/embedded-signup/preflight');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> exchangeEmbeddedSignup({
    required String tenantId,
    required String code,
    required String wabaId,
    required String phoneNumberId,
    required String displayPhoneNumber,
    required String displayName,
    String? verifyToken,
    bool coexistence = true,
    String? messagingAccountId,
    List<String>? messagingAccountIds,
    String? businessId,
    bool? isOnBizApp,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/tenants/$tenantId/whatsapp-onboarding/exchange',
      body: {
        'code': code,
        'waba_id': wabaId,
        'phone_number_id': phoneNumberId,
        'display_phone_number': displayPhoneNumber,
        'display_name': displayName,
        if (verifyToken != null) 'verify_token': verifyToken,
        'coexistence': coexistence,
        if (messagingAccountId != null && messagingAccountId.isNotEmpty)
          'messaging_account_id': messagingAccountId,
        if (messagingAccountIds != null && messagingAccountIds.isNotEmpty)
          'messaging_account_ids': messagingAccountIds,
        if (businessId != null && businessId.isNotEmpty) 'business_id': businessId,
        if (isOnBizApp != null) 'is_on_biz_app': isOnBizApp,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

final whatsAppOnboardingService = WhatsAppOnboardingService(apiClient: apiClient);
