import 'api_client.dart';

Map<String, dynamic> _asMap(dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

List<Map<String, dynamic>> _asList(dynamic raw) =>
    raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false) : const [];

String _q(String? tenantId) => tenantId == null || tenantId.isEmpty ? '' : '?tenant_id=${Uri.encodeQueryComponent(tenantId)}';

/// Billing V2 (dual mode) — tenant e superadmin.
class BillingV2Service {
  BillingV2Service({ApiClient? client}) : _client = client ?? apiClient;

  final ApiClient _client;

  // ------------------------------------------------------------- tenant
  Future<Map<String, dynamic>> summary({String? tenantId}) async =>
      _asMap(await _client.get('/api/v1/billing/v2/summary${_q(tenantId)}'));

  Future<List<Map<String, dynamic>>> ledger({String? tenantId}) async =>
      _asList(_asMap(await _client.get('/api/v1/billing/v2/ledger${_q(tenantId)}'))['items']);

  Future<Map<String, dynamic>> topups({String? tenantId}) async =>
      _asMap(await _client.get('/api/v1/billing/v2/topups${_q(tenantId)}'));

  Future<Map<String, dynamic>> createTopupCheckout({required String itemCode, int? units, String? tenantId}) async =>
      _asMap(await _client.post('/api/v1/billing/v2/topups/checkout', body: {
        'item_code': itemCode,
        if (units != null) 'units': units,
        if (tenantId != null) 'tenant_id': tenantId,
      }));

  // ------------------------------------------------------------- superadmin
  Future<Map<String, dynamic>> tenantConfig(String tenantId) async =>
      _asMap(await _client.get('/api/v1/admin/billing/tenants/${Uri.encodeComponent(tenantId)}/config'));

  Future<Map<String, dynamic>> tenantDashboard(String tenantId) async =>
      _asMap(await _client.get('/api/v1/admin/billing/tenants/${Uri.encodeComponent(tenantId)}/dashboard'));

  Future<Map<String, dynamic>> setBillingMode(String tenantId, {required String? mode, required String reason}) async =>
      _asMap(await _client.patch('/api/v1/admin/billing/tenants/${Uri.encodeComponent(tenantId)}/billing-mode', body: {
        'billing_mode': mode,
        'reason': reason,
        'confirm': true,
      }));

  Future<Map<String, dynamic>> assignPlan(
    String tenantId, {
    required String planCode,
    required String reason,
    String? billingMode,
    int? operationalAllowance,
    String? monthlyPrice,
  }) async =>
      _asMap(await _client.post('/api/v1/admin/billing/tenants/${Uri.encodeComponent(tenantId)}/plan', body: {
        'plan_code': planCode,
        'reason': reason,
        if (billingMode != null) 'billing_mode': billingMode,
        if (operationalAllowance != null) 'operational_allowance': operationalAllowance,
        if (monthlyPrice != null && monthlyPrice.isNotEmpty) 'monthly_price': monthlyPrice,
      }));

  Future<Map<String, dynamic>> manualGrant(String tenantId,
          {required String unitType, required int units, required String reason}) async =>
      _asMap(await _client.post('/api/v1/admin/billing/tenants/${Uri.encodeComponent(tenantId)}/grants', body: {
        'unit_type': unitType,
        'units': units,
        'reason': reason,
      }));

  Future<Map<String, dynamic>> markPurchasePaid(String purchaseId, {required String reason}) async =>
      _asMap(await _client.post('/api/v1/admin/billing/purchases/${Uri.encodeComponent(purchaseId)}/mark-paid',
          body: {'reason': reason}));

  Future<List<Map<String, dynamic>>> overview() async =>
      _asList(_asMap(await _client.get('/api/v1/admin/billing/overview'))['tenants']);

  Future<List<Map<String, dynamic>>> rateCards() async =>
      _asList(_asMap(await _client.get('/api/v1/admin/billing/rate-cards'))['rate_cards']);

  Future<void> createRateVersion(Map<String, dynamic> payload) async {
    await _client.post('/api/v1/admin/billing/rate-cards', body: payload);
  }

  Future<void> markRateReviewed(int cardId,
      {required String sourceCheckedAt, String? sourceReference, required String reason}) async {
    await _client.post('/api/v1/admin/billing/rate-cards/$cardId/reviewed', body: {
      'source_checked_at': sourceCheckedAt,
      if (sourceReference != null && sourceReference.isNotEmpty) 'source_reference': sourceReference,
      'reason': reason,
    });
  }

  Future<Map<String, dynamic>> catalog() async => _asMap(await _client.get('/api/v1/admin/billing/catalog'));

  Future<List<Map<String, dynamic>>> costConfig() async =>
      _asList(_asMap(await _client.get('/api/v1/admin/billing/cost-config'))['items']);

  Future<void> updateCostConfig(String key, {required String? value, required String reason}) async {
    await _client.put('/api/v1/admin/billing/cost-config/${Uri.encodeComponent(key)}',
        body: {'value': value, 'reason': reason});
  }

  Future<Map<String, dynamic>> marginSimulation(Map<String, dynamic> payload) async =>
      _asMap(await _client.post('/api/v1/admin/billing/margin-simulation', body: payload));

  Future<List<Map<String, dynamic>>> reconciliation() async =>
      _asList(_asMap(await _client.get('/api/v1/admin/billing/reconciliation'))['items']);

  Future<void> resolveReconciliation(String reservationId,
      {required String tenantId, required String action, required String reason}) async {
    await _client.post('/api/v1/admin/billing/reconciliation/${Uri.encodeComponent(reservationId)}', body: {
      'tenant_id': tenantId,
      'action': action,
      'reason': reason,
    });
  }
}

final billingV2Service = BillingV2Service();
