class CampaignPlanSnapshotModel {
  CampaignPlanSnapshotModel({
    required this.plan,
    required this.status,
    required this.usedMessages,
    required this.monthlyMessageLimit,
    this.renewalDate,
  });

  final String plan;
  final String status;
  final int usedMessages;
  final int monthlyMessageLimit;
  final DateTime? renewalDate;

  factory CampaignPlanSnapshotModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return CampaignPlanSnapshotModel(
        plan: '',
        status: '',
        usedMessages: 0,
        monthlyMessageLimit: 0,
      );
    }
    return CampaignPlanSnapshotModel(
      plan: json['plan']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      usedMessages: (json['used_messages'] as num?)?.toInt() ?? 0,
      monthlyMessageLimit: (json['monthly_message_limit'] as num?)?.toInt() ?? 0,
      renewalDate: DateTime.tryParse(json['renewal_date']?.toString() ?? ''),
    );
  }
}

class CampaignSendReadinessModel {
  CampaignSendReadinessModel({
    required this.sendsEnabled,
    this.sendsBlockedCode,
    this.sendsBlockedReason,
    this.planSnapshot,
  });

  final bool sendsEnabled;
  final String? sendsBlockedCode;
  final String? sendsBlockedReason;
  final CampaignPlanSnapshotModel? planSnapshot;

  factory CampaignSendReadinessModel.fromJson(Map<String, dynamic> json) {
    return CampaignSendReadinessModel(
      sendsEnabled: json['sends_enabled'] == true,
      sendsBlockedCode: json['sends_blocked_code']?.toString(),
      sendsBlockedReason: json['sends_blocked_reason']?.toString(),
      planSnapshot: json['plan_snapshot'] is Map<String, dynamic>
          ? CampaignPlanSnapshotModel.fromJson(json['plan_snapshot'] as Map<String, dynamic>)
          : null,
    );
  }
}

class CampaignRecipientRowModel {
  CampaignRecipientRowModel({
    required this.rowNumber,
    required this.phone,
    required this.status,
    this.bodyParams = const {},
    this.consentOk = false,
    this.errorMessage,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
  });

  final int rowNumber;
  final String phone;
  final String status;
  final Map<String, String> bodyParams;
  final bool consentOk;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  factory CampaignRecipientRowModel.fromJson(Map<String, dynamic> json) {
    final rawParams = json['body_params'];
    final params = <String, String>{};
    if (rawParams is Map) {
      rawParams.forEach((k, v) => params['$k'] = '$v');
    }
    return CampaignRecipientRowModel(
      rowNumber: (json['row_number'] as num?)?.toInt() ?? 0,
      phone: json['phone']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      bodyParams: params,
      consentOk: json['consent_ok'] == true,
      errorMessage: json['error_message']?.toString(),
      sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(json['delivered_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
    );
  }
}

class CampaignDetailModel {
  CampaignDetailModel({required this.campaign, required this.recipients});

  final CampaignSummaryModel campaign;
  final List<CampaignRecipientRowModel> recipients;

  factory CampaignDetailModel.fromJson(Map<String, dynamic> json) {
    return CampaignDetailModel(
      campaign: CampaignSummaryModel.fromJson(
        json['campaign'] as Map<String, dynamic>? ?? const {},
      ),
      recipients: (json['recipients'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CampaignRecipientRowModel.fromJson)
              .toList() ??
          const [],
    );
  }
}

class CampaignSummaryModel {
  CampaignSummaryModel({
    required this.id,
    required this.name,
    required this.status,
    this.accountKey,
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
  final String? accountKey;
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

  /// Mensagens aceitas pela Meta, inclusive as que já evoluíram para entregue/lida/falha.
  int get messagesSent =>
      sentCount + deliveredCount + readCount + failedCount + uncertainCount;

  int get messagesDelivered => deliveredCount + readCount;

  /// Percentual 0–100. Denominador: entregues + lidas + falhas + incertas.
  double? get deliveryRatePercent {
    final known = messagesDelivered + failedCount + uncertainCount;
    if (known <= 0) return null;
    return messagesDelivered / known * 100;
  }

  double get processingProgress {
    if (totalRecipients <= 0) return 0;
    final done = messagesSent.clamp(0, totalRecipients);
    return done / totalRecipients;
  }

  factory CampaignSummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? v) =>
        v == null || v.isEmpty ? null : DateTime.tryParse(v);

    return CampaignSummaryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      accountKey: json['account_key']?.toString(),
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

class CampaignRecipientPreviewModel {
  CampaignRecipientPreviewModel({
    required this.rowNumber,
    required this.phone,
    this.bodyParams = const {},
    this.consentOk = false,
    this.errors = const [],
  });

  final int rowNumber;
  final String phone;
  final Map<String, String> bodyParams;
  final bool consentOk;
  final List<String> errors;

  factory CampaignRecipientPreviewModel.fromJson(Map<String, dynamic> json) {
    final raw = json['body_params'];
    final params = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) => params['$k'] = '$v');
    }
    return CampaignRecipientPreviewModel(
      rowNumber: (json['row_number'] as num?)?.toInt() ?? 0,
      phone: json['phone']?.toString() ?? '',
      bodyParams: params,
      consentOk: json['consent_ok'] == true,
      errors: (json['errors'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

class CampaignValidationModel {
  CampaignValidationModel({
    required this.campaignId,
    required this.totalRows,
    required this.validRows,
    required this.duplicatePhones,
    required this.invalidRows,
    required this.consentMissingRows,
    required this.recipients,
    required this.errors,
    required this.sendsEnabled,
    this.sendsBlockedReason,
    this.sendsBlockedCode,
    this.planSnapshot,
    this.estimate = const {},
    this.metaDisclaimer,
  });

  final String? campaignId;
  final int totalRows;
  final int validRows;
  final int duplicatePhones;
  final int invalidRows;
  final int consentMissingRows;
  final List<CampaignRecipientPreviewModel> recipients;
  final List<String> errors;
  final bool sendsEnabled;
  final String? sendsBlockedReason;
  final String? sendsBlockedCode;
  final CampaignPlanSnapshotModel? planSnapshot;
  final Map<String, dynamic> estimate;
  final String? metaDisclaimer;

  bool get spreadsheetValid => validRows > 0 && invalidRows == 0;

  factory CampaignValidationModel.fromJson(Map<String, dynamic> json) {
    return CampaignValidationModel(
      campaignId: json['campaign_id']?.toString(),
      totalRows: (json['total_rows'] as num?)?.toInt() ?? 0,
      validRows: (json['valid_rows'] as num?)?.toInt() ?? 0,
      duplicatePhones: (json['duplicate_phones'] as num?)?.toInt() ?? 0,
      invalidRows: (json['invalid_rows'] as num?)?.toInt() ?? 0,
      consentMissingRows: (json['consent_missing_rows'] as num?)?.toInt() ?? 0,
      recipients: (json['recipients'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CampaignRecipientPreviewModel.fromJson)
              .toList() ??
          const [],
      errors: (json['errors'] as List?)?.map((e) => '$e').toList() ?? const [],
      sendsEnabled: json['sends_enabled'] == true,
      sendsBlockedReason: json['sends_blocked_reason']?.toString(),
      sendsBlockedCode: json['sends_blocked_code']?.toString(),
      planSnapshot: json['plan_snapshot'] is Map<String, dynamic>
          ? CampaignPlanSnapshotModel.fromJson(json['plan_snapshot'] as Map<String, dynamic>)
          : null,
      estimate: json['estimate'] is Map<String, dynamic>
          ? json['estimate'] as Map<String, dynamic>
          : const {},
      metaDisclaimer: json['meta_disclaimer']?.toString(),
    );
  }
}