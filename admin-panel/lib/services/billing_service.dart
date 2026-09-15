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

class MetaRateCard {
  MetaRateCard({
    required this.market,
    required this.currency,
    required this.category,
    required this.rateMicros,
    this.notes,
    this.sourceReference,
  });

  final String market;
  final String currency;
  final String category;
  final int rateMicros;
  final String? notes;
  final String? sourceReference;

  double get rate => rateMicros / 1000000.0;

  factory MetaRateCard.fromJson(Map<String, dynamic> json) {
    return MetaRateCard(
      market: json['market']?.toString() ?? 'BR',
      currency: json['currency']?.toString() ?? 'BRL',
      category: json['category']?.toString() ?? '',
      rateMicros: int.tryParse(json['rate_micros']?.toString() ?? '') ?? 0,
      notes: json['notes']?.toString(),
      sourceReference: json['source_reference']?.toString(),
    );
  }

  static List<MetaRateCard> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => MetaRateCard.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    if (data is Map) {
      final items = data['items'] ?? data['rates'];
      if (items is List) return listFromJson(items);
    }
    return const <MetaRateCard>[];
  }
}

class FiscalDocument {
  FiscalDocument({
    required this.id,
    required this.competence,
    required this.status,
    required this.amountCents,
    required this.currency,
    this.documentNumber,
    this.downloadUrl,
  });

  final String id;
  final String competence;
  final String status;
  final int amountCents;
  final String currency;
  final String? documentNumber;
  final String? downloadUrl;

  bool get isConfigured =>
      status.toLowerCase() != 'not_configured' &&
      status.toLowerCase() != 'unavailable';

  factory FiscalDocument.fromJson(Map<String, dynamic> json) {
    return FiscalDocument(
      id: json['id']?.toString() ?? '',
      competence: json['competence']?.toString() ?? '',
      status: json['status']?.toString() ?? 'not_configured',
      amountCents: int.tryParse(json['amount_cents']?.toString() ?? '') ?? 0,
      currency: json['currency']?.toString() ?? 'BRL',
      documentNumber: json['document_number']?.toString(),
      downloadUrl: json['download_url']?.toString(),
    );
  }

  static List<FiscalDocument> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => FiscalDocument.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    if (data is Map) {
      final items = data['documents'] ?? data['items'];
      if (items is List) return listFromJson(items);
    }
    return const <FiscalDocument>[];
  }
}

/// True when API payload indicates fiscal provider is not configured.
bool fiscalProviderConfigured(dynamic data) {
  if (data is Map && data['configured'] == false) return false;
  return true;
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

  /// Meta category rate estimates (BR).
  Future<List<MetaRateCard>> fetchMetaRates() async {
    try {
      final data = await _apiClient.get('/api/v1/usage/meta-rates');
      return MetaRateCard.listFromJson(data);
    } on ApiException catch (err) {
      if (err.statusCode == 404) {
        final data = await _apiClient.get('/api/v1/billing/meta-rates');
        return MetaRateCard.listFromJson(data);
      }
      rethrow;
    }
  }

  Future<List<FiscalDocument>> fetchFiscalDocuments() async {
    try {
      final data = await _apiClient.get('/api/v1/fiscal/documents');
      return FiscalDocument.listFromJson(data);
    } on ApiException catch (err) {
      if (err.statusCode == 404) return const <FiscalDocument>[];
      rethrow;
    }
  }
}

final billingService = BillingService(apiClient: apiClient);

