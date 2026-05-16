import 'api_client.dart';

class Lead {
  Lead({
    required this.id,
    required this.name,
    required this.company,
    required this.email,
    required this.whatsapp,
    required this.objective,
    this.segment,
    this.monthlyVolume,
    this.teamSize,
    this.currentTools,
    this.bestContactTime,
    this.source = 'landing',
    this.status = 'new',
    this.notes,
    this.assignedTo,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String company;
  final String? segment;
  final String email;
  final String whatsapp;
  final String objective;
  final String? monthlyVolume;
  final String? teamSize;
  final String? currentTools;
  final String? bestContactTime;
  final String source;
  final String status;
  final String? notes;
  final String? assignedTo;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Lead.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    return Lead(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      company: (json['company'] ?? '').toString(),
      segment: json['segment'] as String?,
      email: (json['email'] ?? '').toString(),
      whatsapp: (json['whatsapp'] ?? '').toString(),
      objective: (json['objective'] ?? '').toString(),
      monthlyVolume: json['monthly_volume'] as String?,
      teamSize: json['team_size'] as String?,
      currentTools: json['current_tools'] as String?,
      bestContactTime: json['best_contact_time'] as String?,
      source: (json['source'] ?? 'landing').toString(),
      status: (json['status'] ?? 'new').toString(),
      notes: json['notes'] as String?,
      assignedTo: json['assigned_to']?.toString(),
      metadata: (json['metadata'] is Map<String, dynamic>)
          ? json['metadata'] as Map<String, dynamic>
          : null,
      createdAt: parse(json['created_at']),
      updatedAt: parse(json['updated_at']),
    );
  }
}

class LeadSummary {
  LeadSummary({required this.total, required this.byStatus});

  final int total;
  final Map<String, int> byStatus;

  factory LeadSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['by_status'];
    final map = <String, int>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key == null) return;
        map[key.toString()] = (value is num) ? value.toInt() : int.tryParse('$value') ?? 0;
      });
    }
    return LeadSummary(
      total: (json['total'] is num) ? (json['total'] as num).toInt() : 0,
      byStatus: map,
    );
  }
}

class LeadService {
  LeadService({ApiClient? client}) : _client = client ?? apiClient;

  final ApiClient _client;

  Future<Lead> submitPublicLead({
    required String name,
    required String company,
    String? segment,
    required String email,
    required String whatsapp,
    required String objective,
    String? monthlyVolume,
    String? teamSize,
    String? currentTools,
    String? bestContactTime,
    String source = 'landing',
    Map<String, dynamic>? metadata,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'company': company.trim(),
      'segment': (segment ?? '').trim().isEmpty ? null : segment!.trim(),
      'email': email.trim().toLowerCase(),
      'whatsapp': whatsapp.trim(),
      'objective': objective.trim(),
      'monthly_volume': (monthlyVolume ?? '').trim().isEmpty ? null : monthlyVolume!.trim(),
      'team_size': (teamSize ?? '').trim().isEmpty ? null : teamSize!.trim(),
      'current_tools': (currentTools ?? '').trim().isEmpty ? null : currentTools!.trim(),
      'best_contact_time':
          (bestContactTime ?? '').trim().isEmpty ? null : bestContactTime!.trim(),
      'source': source,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };
    final result = await _client.post('/api/v1/public/leads', body: payload);
    return Lead.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<List<Lead>> listLeads({
    String? status,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = <String>[];
    if (status != null && status.isNotEmpty) query.add('status=${Uri.encodeQueryComponent(status)}');
    if (search != null && search.isNotEmpty) query.add('search=${Uri.encodeQueryComponent(search)}');
    query.add('limit=$limit');
    query.add('offset=$offset');
    final result = await _client.get('/api/v1/admin/leads?${query.join('&')}');
    if (result is! List) return const <Lead>[];
    return result
        .whereType<Map>()
        .map((item) => Lead.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<LeadSummary> summary() async {
    final result = await _client.get('/api/v1/admin/leads/summary');
    if (result is! Map) return LeadSummary(total: 0, byStatus: const {});
    return LeadSummary.fromJson(Map<String, dynamic>.from(result));
  }

  Future<Lead> updateLead({
    required String leadId,
    String? status,
    String? notes,
    int? assignedTo,
  }) async {
    final payload = <String, dynamic>{};
    if (status != null) payload['status'] = status;
    if (notes != null) payload['notes'] = notes;
    if (assignedTo != null) payload['assigned_to'] = assignedTo;
    final result = await _client.patch('/api/v1/admin/leads/$leadId', body: payload);
    return Lead.fromJson(Map<String, dynamic>.from(result as Map));
  }
}

final leadService = LeadService();
