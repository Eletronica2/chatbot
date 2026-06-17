import 'api_client.dart';

class WhatsAppOnboardingService {
  WhatsAppOnboardingService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getEmbeddedSignupConfig() async {
    final data = await _apiClient.get('/api/v1/meta/embedded-signup/config');
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
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }
}

final whatsAppOnboardingService = WhatsAppOnboardingService(apiClient: apiClient);
