import 'dart:convert';

import 'api_client.dart';

String apiErrorText(Object error) {
  if (error is! ApiException) return '$error';
  try {
    final decoded = jsonDecode(error.message);
    final detail = decoded is Map ? decoded['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is Map && detail['message'] != null) return detail['message'].toString();
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) return first['msg'].toString();
    }
  } catch (_) {}
  return error.message.length > 240 ? error.message.substring(0, 240) : error.message;
}

const kBillingModeCustomerDirect = 'customer_direct';
const kBillingModeSolutionPartner = 'solution_partner_credit_line';

String billingModeLabel(String? mode) => mode == kBillingModeSolutionPartner
    ? 'Atende Ai (créditos — Solution Partner)'
    : 'Cliente paga a Meta diretamente';

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

double _toDouble(dynamic v) => _toDoubleOrNull(v) ?? 0;

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList(growable: false);
}

Map<String, dynamic>? _map(dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : null;

class CatalogPlanOption {
  CatalogPlanOption({
    required this.code,
    required this.planKey,
    required this.label,
    required this.catalogVersion,
    required this.status,
    this.price,
    this.operationalUnits,
    this.isCustom = false,
  });

  final String code;
  final String planKey;
  final String label;
  final String catalogVersion;
  final String status;
  final double? price;
  final int? operationalUnits;
  final bool isCustom;

  bool get isActive => status == 'active';

  factory CatalogPlanOption.fromJson(Map<String, dynamic> json) => CatalogPlanOption(
        code: json['code']?.toString() ?? '',
        planKey: json['plan_key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        catalogVersion: json['catalog_version']?.toString() ?? '',
        status: json['status']?.toString() ?? 'active',
        price: _toDoubleOrNull(json['price']),
        operationalUnits: _toIntOrNull(json['operational_units']),
        isCustom: json['is_custom'] == true || json['is_custom'] == 1,
      );
}

class MarginCheck {
  MarginCheck(this.raw);

  final Map<String, dynamic> raw;

  String get status => raw['status']?.toString() ?? 'partial';
  String get statusLabel => raw['status_label']?.toString() ?? status;
  String? get marginPercent => raw['margin_percent']?.toString();
  String? get minimumSafePrice => raw['minimum_safe_price']?.toString();
  String? get metaCustomerEstimate => raw['meta_customer_estimate']?.toString();
  String? get contribution => raw['contribution']?.toString();
  List<String> get unknownComponents => _stringList(raw['unknown_components']);
  Map<String, dynamic> get costs => _map(raw['costs']) ?? const {};
  Map<String, dynamic> get discount => _map(raw['discount']) ?? const {};
  bool get allowed => discount['allowed'] != false;
  bool get requiresReason => discount['requires_reason'] == true;
  String get discountMessage => discount['message']?.toString() ?? '';
  String get discountCode => discount['code']?.toString() ?? '';
}

class PlanRecommendation {
  PlanRecommendation({
    required this.plan,
    required this.planCode,
    required this.planLabel,
    required this.catalogVersion,
    required this.billingMode,
    required this.monthlyValue,
    required this.isCustom,
    required this.setupFee,
    required this.monthlyMessageLimit,
    required this.includedItems,
    required this.rationale,
    this.operationalVolume,
    this.operationalAnswer,
    this.marketingVolume,
    this.marketingAnswer,
    this.marketingUnitPrice,
    this.marketingEstimate,
    this.warning,
    this.topupOffers = const [],
    this.margin,
  });

  final String plan;
  final String planCode;
  final String planLabel;
  final String catalogVersion;
  final String billingMode;
  final double? monthlyValue;
  final bool isCustom;
  final double setupFee;
  final int? monthlyMessageLimit;
  final List<String> includedItems;
  final String rationale;
  final int? operationalVolume;
  final String? operationalAnswer;
  final int? marketingVolume;
  final String? marketingAnswer;
  final double? marketingUnitPrice;
  final double? marketingEstimate;
  final String? warning;
  final List<Map<String, dynamic>> topupOffers;
  final MarginCheck? margin;

  factory PlanRecommendation.fromJson(Map<String, dynamic> json) {
    final topups = json['topup_offers'];
    final margin = _map(json['margin']);
    return PlanRecommendation(
      plan: json['plan']?.toString() ?? '',
      planCode: json['plan_code']?.toString() ?? '',
      planLabel: json['plan_label']?.toString() ?? '',
      catalogVersion: json['catalog_version']?.toString() ?? '',
      billingMode: json['billing_mode']?.toString() ?? kBillingModeCustomerDirect,
      monthlyValue: _toDoubleOrNull(json['monthly_value']),
      isCustom: json['is_custom'] == true,
      setupFee: _toDouble(json['setup_fee']),
      monthlyMessageLimit: _toIntOrNull(json['monthly_message_limit']),
      includedItems: _stringList(json['included_items']),
      rationale: json['rationale']?.toString() ?? '',
      operationalVolume: _toIntOrNull(json['operational_volume']),
      operationalAnswer: json['operational_answer']?.toString(),
      marketingVolume: _toIntOrNull(json['marketing_volume']),
      marketingAnswer: json['marketing_answer']?.toString(),
      marketingUnitPrice: _toDoubleOrNull(json['marketing_unit_price']),
      marketingEstimate: _toDoubleOrNull(json['marketing_estimate']),
      warning: json['warning']?.toString(),
      topupOffers: topups is List
          ? topups.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
          : const [],
      margin: margin == null ? null : MarginCheck(margin),
    );
  }
}

class ProposalRecord {
  ProposalRecord({
    required this.id,
    this.leadId,
    this.tenantId,
    required this.companyName,
    required this.contactName,
    required this.contactEmail,
    this.contactWhatsapp,
    required this.plan,
    this.planCode,
    this.catalogVersion,
    this.billingMode,
    this.isLegacy = false,
    required this.monthlyValue,
    required this.setupFee,
    required this.monthlyMessageLimit,
    this.operationalVolume,
    this.marketingVolume,
    this.marketingEstimate,
    required this.includedItems,
    this.marginSnapshot,
    required this.validityDays,
    required this.status,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? leadId;
  final String? tenantId;
  final String companyName;
  final String contactName;
  final String contactEmail;
  final String? contactWhatsapp;
  final String plan;
  final String? planCode;
  final String? catalogVersion;
  final String? billingMode;
  final bool isLegacy;
  final double monthlyValue;
  final double setupFee;
  final int monthlyMessageLimit;
  final int? operationalVolume;
  final int? marketingVolume;
  final double? marketingEstimate;
  final List<String> includedItems;
  final Map<String, dynamic>? marginSnapshot;
  final int validityDays;
  final String status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProposalRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return ProposalRecord(
      id: json['id']?.toString() ?? '',
      leadId: json['lead_id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      companyName: json['company_name']?.toString() ?? '',
      contactName: json['contact_name']?.toString() ?? '',
      contactEmail: json['contact_email']?.toString() ?? '',
      contactWhatsapp: json['contact_whatsapp']?.toString(),
      plan: json['plan']?.toString() ?? 'starter',
      planCode: json['plan_code']?.toString(),
      catalogVersion: json['catalog_version']?.toString(),
      billingMode: json['billing_mode']?.toString(),
      isLegacy: json['is_legacy'] == true,
      monthlyValue: _toDouble(json['monthly_value']),
      setupFee: _toDouble(json['setup_fee']),
      monthlyMessageLimit: _toIntOrNull(json['monthly_message_limit']) ?? 1000,
      operationalVolume: _toIntOrNull(json['operational_volume']),
      marketingVolume: _toIntOrNull(json['marketing_volume']),
      marketingEstimate: _toDoubleOrNull(json['marketing_estimate']),
      includedItems: _stringList(json['included_items']),
      marginSnapshot: _map(json['margin_snapshot']),
      validityDays: _toIntOrNull(json['validity_days']) ?? 7,
      status: json['status']?.toString() ?? 'draft',
      notes: json['notes']?.toString(),
      createdAt: parse(json['created_at']),
      updatedAt: parse(json['updated_at']),
    );
  }
}

class ConvertLeadResult {
  ConvertLeadResult({
    required this.tenant,
    this.billing,
    this.inviteToken,
    this.inviteExpiresAt,
    this.inviteUrl,
    this.emailStatus,
    this.emailError,
    this.ownerEmail,
    this.ownerName,
    this.ownerWhatsapp,
  });

  final Map<String, dynamic> tenant;
  final Map<String, dynamic>? billing;
  final String? inviteToken;
  final DateTime? inviteExpiresAt;
  final String? inviteUrl;
  final String? emailStatus;
  final String? emailError;
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerWhatsapp;

  factory ConvertLeadResult.fromJson(Map<String, dynamic> json) {
    final t = json['tenant'];
    String? str(String key) {
      final v = json[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return ConvertLeadResult(
      tenant: t is Map<String, dynamic> ? Map<String, dynamic>.from(t) : {},
      billing: _map(json['billing']),
      inviteToken: str('invite_token'),
      inviteExpiresAt:
          json['invite_expires_at'] == null ? null : DateTime.tryParse(json['invite_expires_at'].toString()),
      inviteUrl: str('invite_url'),
      emailStatus: str('email_status'),
      emailError: str('email_error'),
      ownerEmail: str('owner_email'),
      ownerName: str('owner_name'),
      ownerWhatsapp: str('owner_whatsapp'),
    );
  }

  String? get tenantId => tenant['tenant_id']?.toString();
  String get tenantName => tenant['name']?.toString() ?? tenantId ?? '';
  bool get emailSent => emailStatus == 'sent';
}

class ProposalApiService {
  ProposalApiService({ApiClient? client}) : _client = client ?? apiClient;

  final ApiClient _client;

  Future<PlanRecommendation> recommendationForLead(int leadId, {String? billingMode}) async {
    final q = billingMode == null ? '' : '?billing_mode=$billingMode';
    final data = await _client.get('/api/v1/admin/leads/$leadId/recommendation$q');
    return PlanRecommendation.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<CatalogPlanOption>> catalogPlans() async {
    final data = await _client.get('/api/v1/admin/billing/catalog');
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['kind'] == 'plan')
        .map(CatalogPlanOption.fromJson)
        .toList(growable: false);
  }

  Future<MarginCheck> marginCheck({
    required String? planCode,
    required double price,
    required int operationalUnits,
    required String billingMode,
    String? overrideReason,
  }) async {
    final data = await _client.post('/api/v1/admin/proposals/margin-check', body: {
      if (planCode != null) 'plan_code': planCode,
      'price': price.toStringAsFixed(2),
      'operational_units': operationalUnits,
      'billing_mode': billingMode,
      if (overrideReason != null && overrideReason.trim().isNotEmpty) 'margin_override_reason': overrideReason.trim(),
    });
    return MarginCheck(Map<String, dynamic>.from(data as Map));
  }

  Future<List<ProposalRecord>> list({int? leadId, String? status}) async {
    final q = <String>[];
    if (leadId != null) q.add('lead_id=$leadId');
    if (status != null && status.isNotEmpty) q.add('status=$status');
    final path = '/api/v1/admin/proposals${q.isEmpty ? '' : '?${q.join('&')}'}';
    final data = await _client.get(path);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ProposalRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<ProposalRecord> create({
    required int? leadId,
    required String companyName,
    required String contactName,
    required String contactEmail,
    String? contactWhatsapp,
    required String planCode,
    required String billingMode,
    required double monthlyValue,
    required double setupFee,
    required int monthlyMessageLimit,
    int? operationalVolume,
    int? marketingVolume,
    required List<String> includedItems,
    required int validityDays,
    String status = 'draft',
    String? notes,
    String? marginOverrideReason,
  }) async {
    final body = <String, dynamic>{
      if (leadId != null) 'lead_id': leadId,
      'company_name': companyName,
      'contact_name': contactName,
      'contact_email': contactEmail,
      if (contactWhatsapp != null && contactWhatsapp.isNotEmpty) 'contact_whatsapp': contactWhatsapp,
      'plan_code': planCode,
      'billing_mode': billingMode,
      'monthly_value': monthlyValue.toStringAsFixed(2),
      'setup_fee': setupFee.toStringAsFixed(2),
      'monthly_message_limit': monthlyMessageLimit,
      if (operationalVolume != null) 'operational_volume': operationalVolume,
      if (marketingVolume != null) 'marketing_volume': marketingVolume,
      'included_items': includedItems,
      'validity_days': validityDays,
      'status': status,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (marginOverrideReason != null && marginOverrideReason.trim().isNotEmpty)
        'margin_override_reason': marginOverrideReason.trim(),
    };
    final data = await _client.post('/api/v1/admin/proposals', body: body);
    return ProposalRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ProposalRecord> patch(int proposalId,
      {String? status, String? notes, double? monthlyValue, double? setupFee, String? marginOverrideReason}) async {
    final body = <String, dynamic>{
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (monthlyValue != null) 'monthly_value': monthlyValue.toStringAsFixed(2),
      if (setupFee != null) 'setup_fee': setupFee.toStringAsFixed(2),
      if (marginOverrideReason != null) 'margin_override_reason': marginOverrideReason,
    };
    final data = await _client.patch('/api/v1/admin/proposals/$proposalId', body: body);
    return ProposalRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ConvertLeadResult> convertLead({
    required int leadId,
    required String tenantId,
    required String tenantEmail,
    required String ownerName,
    required String ownerEmail,
    required String planCode,
    required int monthlyMessageLimit,
    String? billingMode,
    double? monthlyPrice,
    String? ownerPassword,
    String? marginOverrideReason,
  }) async {
    final body = <String, dynamic>{
      'tenant_id': tenantId,
      'tenant_email': tenantEmail,
      'owner_name': ownerName,
      'owner_email': ownerEmail,
      'plan_code': planCode,
      'monthly_message_limit': monthlyMessageLimit,
      if (billingMode != null) 'billing_mode': billingMode,
      if (monthlyPrice != null) 'monthly_price': monthlyPrice.toStringAsFixed(2),
      if (ownerPassword != null && ownerPassword.isNotEmpty) 'owner_password': ownerPassword,
      if (marginOverrideReason != null && marginOverrideReason.trim().isNotEmpty)
        'margin_override_reason': marginOverrideReason.trim(),
    };
    final data = await _client.post('/api/v1/admin/leads/$leadId/convert', body: body);
    return ConvertLeadResult.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

final proposalApiService = ProposalApiService();
