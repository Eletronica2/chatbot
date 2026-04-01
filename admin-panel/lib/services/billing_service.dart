import '../models/billing_summary.dart';
import 'api_client.dart';

class BillingCheckoutSessionModel {
  BillingCheckoutSessionModel({
    required this.checkoutUrl,
    required this.sessionId,
    required this.plan,
    required this.provider,
  });

  final String checkoutUrl;
  final String sessionId;
  final String plan;
  final String provider;

  factory BillingCheckoutSessionModel.fromJson(Map<String, dynamic> json) {
    return BillingCheckoutSessionModel(
      checkoutUrl: json['checkout_url']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      plan: json['plan']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'stripe',
    );
  }
}

class BillingPortalSessionModel {
  BillingPortalSessionModel({
    required this.portalUrl,
    required this.provider,
  });

  final String portalUrl;
  final String provider;

  factory BillingPortalSessionModel.fromJson(Map<String, dynamic> json) {
    return BillingPortalSessionModel(
      portalUrl: json['portal_url']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'stripe',
    );
  }
}

class BillingService {
  BillingService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<BillingSummaryModel> fetchSummary() async {
    final data = await _apiClient.get('/api/v1/billing/summary');
    return BillingSummaryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<BillingCheckoutSessionModel> createCheckoutSession(String plan) async {
    final data = await _apiClient.post(
      '/api/v1/billing/checkout-session',
      body: {'plan': plan},
    );
    return BillingCheckoutSessionModel.fromJson(data as Map<String, dynamic>);
  }

  Future<BillingPortalSessionModel> createPortalSession({
    String? returnUrl,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/billing/portal-session',
      body: {
        if (returnUrl != null && returnUrl.trim().isNotEmpty)
          'return_url': returnUrl.trim(),
      },
    );
    return BillingPortalSessionModel.fromJson(data as Map<String, dynamic>);
  }
}

final billingService = BillingService(apiClient: apiClient);

