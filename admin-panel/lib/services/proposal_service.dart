import 'api_client.dart';

class PlanRecommendation {
  PlanRecommendation({
    required this.plan,
    required this.planLabel,
    required this.monthlyValue,
    required this.setupFee,
    required this.monthlyMessageLimit,
    required this.includedItems,
    required this.rationale,
  });

  final String plan;
  final String planLabel;
  final double monthlyValue;
  final double setupFee;
  final int monthlyMessageLimit;
  final List<String> includedItems;
  final String rationale;

  factory PlanRecommendation.fromJson(Map<String, dynamic> json) {
    return PlanRecommendation(
      plan: json['plan']?.toString() ?? 'starter',
      planLabel: json['plan_label']?.toString() ?? '',
      monthlyValue: _toDouble(json['monthly_value']),
      setupFee: _toDouble(json['setup_fee']),
      monthlyMessageLimit: (json['monthly_message_limit'] as num?)?.toInt() ?? 1000,
      includedItems: _stringList(json['included_items']),
      rationale: json['rationale']?.toString() ?? '',
    );
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList(growable: false);
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
    required this.monthlyValue,
    required this.setupFee,
    required this.monthlyMessageLimit,
    required this.includedItems,
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
  final double monthlyValue;
  final double setupFee;
  final int monthlyMessageLimit;
  final List<String> includedItems;
  final int validityDays;
  final String status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProposalRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return ProposalRecord(
      id: json['id']?.toString() ?? '',
      leadId: json['lead_id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      companyName: json['company_name']?.toString() ?? '',
      contactName: json['contact_name']?.toString() ?? '',
      contactEmail: json['contact_email']?.toString() ?? '',
      contactWhatsapp: json['contact_whatsapp']?.toString(),
      plan: json['plan']?.toString() ?? 'starter',
      monthlyValue: _toDouble(json['monthly_value']),
      setupFee: _toDouble(json['setup_fee']),
      monthlyMessageLimit: (json['monthly_message_limit'] as num?)?.toInt() ?? 1000,
      includedItems: _stringList(json['included_items']),
      validityDays: (json['validity_days'] as num?)?.toInt() ?? 7,
      status: json['status']?.toString() ?? 'draft',
      notes: json['notes']?.toString(),
      createdAt: parse(json['created_at']),
      updatedAt: parse(json['updated_at']),
    );
  }
}

class ConvertLeadResult {
  ConvertLeadResult({required this.tenant, this.inviteToken, this.inviteExpiresAt});

  final Map<String, dynamic> tenant;
  final String? inviteToken;
  final DateTime? inviteExpiresAt;

  factory ConvertLeadResult.fromJson(Map<String, dynamic> json) {
    final t = json['tenant'];
    return ConvertLeadResult(
      tenant: t is Map<String, dynamic> ? Map<String, dynamic>.from(t) : {},
      inviteToken: json['invite_token']?.toString(),
      inviteExpiresAt:
          json['invite_expires_at'] == null ? null : DateTime.tryParse(json['invite_expires_at'].toString()),
    );
  }

  String? get tenantId => tenant['tenant_id']?.toString();
}

class ProposalApiService {
  ProposalApiService({ApiClient? client}) : _client = client ?? apiClient;

  final ApiClient _client;

  Future<PlanRecommendation> recommendationForLead(int leadId) async {
    final data = await _client.get('/api/v1/admin/leads/$leadId/recommendation');
    return PlanRecommendation.fromJson(Map<String, dynamic>.from(data as Map));
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
    required String plan,
    required double monthlyValue,
    required double setupFee,
    required int monthlyMessageLimit,
    required List<String> includedItems,
    required int validityDays,
    String status = 'draft',
    String? notes,
  }) async {
    final body = <String, dynamic>{
      if (leadId != null) 'lead_id': leadId,
      'company_name': companyName,
      'contact_name': contactName,
      'contact_email': contactEmail,
      if (contactWhatsapp != null && contactWhatsapp.isNotEmpty) 'contact_whatsapp': contactWhatsapp,
      'plan': plan,
      'monthly_value': monthlyValue,
      'setup_fee': setupFee,
      'monthly_message_limit': monthlyMessageLimit,
      'included_items': includedItems,
      'validity_days': validityDays,
      'status': status,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    };
    final data = await _client.post('/api/v1/admin/proposals', body: body);
    return ProposalRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ProposalRecord> patch(int proposalId,
      {String? status, String? notes, double? monthlyValue, double? setupFee}) async {
    final body = <String, dynamic>{
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (monthlyValue != null) 'monthly_value': monthlyValue,
      if (setupFee != null) 'setup_fee': setupFee,
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
    required String plan,
    required int monthlyMessageLimit,
    String? ownerPassword,
  }) async {
    final body = <String, dynamic>{
      'tenant_id': tenantId,
      'tenant_email': tenantEmail,
      'owner_name': ownerName,
      'owner_email': ownerEmail,
      'plan': plan,
      'monthly_message_limit': monthlyMessageLimit,
      if (ownerPassword != null && ownerPassword.isNotEmpty) 'owner_password': ownerPassword,
    };
    final data = await _client.post('/api/v1/admin/leads/$leadId/convert', body: body);
    return ConvertLeadResult.fromJson(Map<String, dynamic>.from(data as Map));
  }
}

final proposalApiService = ProposalApiService();
