class CampaignSummaryModel {
  CampaignSummaryModel({
    required this.id,
    required this.name,
    required this.status,
    required this.templateName,
    required this.templateLanguage,
    required this.templateCategory,
    required this.totalRecipients,
    required this.pendingCount,
    required this.sentCount,
    required this.deliveredCount,
    required this.readCount,
    required this.failedCount,
    required this.uncertainCount,
    this.metaEstimate = const {},
    this.metaDisclaimer,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String name;
  final String status;
  final String templateName;
  final String templateLanguage;
  final String templateCategory;
  final int totalRecipients;
  final int pendingCount;
  final int sentCount;
  final int deliveredCount;
  final int readCount;
  final int failedCount;
  final int uncertainCount;
  final Map<String, dynamic> metaEstimate;
  final String? metaDisclaimer;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory CampaignSummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? v) =>
        v == null || v.isEmpty ? null : DateTime.tryParse(v);

    return CampaignSummaryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      templateName: json['template_name']?.toString() ?? '',
      templateLanguage: json['template_language']?.toString() ?? 'pt_BR',
      templateCategory: json['template_category']?.toString() ?? 'UTILITY',
      totalRecipients: (json['total_recipients'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      readCount: (json['read_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      uncertainCount: (json['uncertain_count'] as num?)?.toInt() ?? 0,
      metaEstimate: json['meta_estimate'] is Map<String, dynamic>
          ? json['meta_estimate'] as Map<String, dynamic>
          : const {},
      metaDisclaimer: json['meta_disclaimer']?.toString(),
      createdAt: parse(json['created_at']?.toString()),
      startedAt: parse(json['started_at']?.toString()),
      completedAt: parse(json['completed_at']?.toString()),
    );
  }
}

class CampaignValidationModel {
  CampaignValidationModel({
    required this.campaignId,
    required this.totalRows,
    required this.validRows,
    required this.duplicatePhones,
    required this.errors,
    required this.sendsEnabled,
    this.sendsBlockedReason,
    this.estimate = const {},
    this.metaDisclaimer,
  });

  final String? campaignId;
  final int totalRows;
  final int validRows;
  final int duplicatePhones;
  final List<String> errors;
  final bool sendsEnabled;
  final String? sendsBlockedReason;
  final Map<String, dynamic> estimate;
  final String? metaDisclaimer;

  factory CampaignValidationModel.fromJson(Map<String, dynamic> json) {
    return CampaignValidationModel(
      campaignId: json['campaign_id']?.toString(),
      totalRows: (json['total_rows'] as num?)?.toInt() ?? 0,
      validRows: (json['valid_rows'] as num?)?.toInt() ?? 0,
      duplicatePhones: (json['duplicate_phones'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as List?)?.map((e) => '$e').toList() ?? const [],
      sendsEnabled: json['sends_enabled'] == true,
      sendsBlockedReason: json['sends_blocked_reason']?.toString(),
      estimate: json['estimate'] is Map<String, dynamic>
          ? json['estimate'] as Map<String, dynamic>
          : const {},
      metaDisclaimer: json['meta_disclaimer']?.toString(),
    );
  }
}