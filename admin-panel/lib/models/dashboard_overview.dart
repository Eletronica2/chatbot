class DashboardKpiModel {
  DashboardKpiModel({
    required this.label,
    required this.value,
    this.helper,
    this.tone = 'default',
  });

  final String label;
  final String value;
  final String? helper;
  final String tone;

  factory DashboardKpiModel.fromJson(Map<String, dynamic> json) {
    return DashboardKpiModel(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      helper: json['helper']?.toString(),
      tone: json['tone']?.toString() ?? 'default',
    );
  }
}

class DashboardPlanBreakdownModel {
  DashboardPlanBreakdownModel({
    required this.plan,
    required this.tenants,
    required this.estimatedMrrCents,
  });

  final String plan;
  final int tenants;
  final int estimatedMrrCents;

  factory DashboardPlanBreakdownModel.fromJson(Map<String, dynamic> json) {
    return DashboardPlanBreakdownModel(
      plan: json['plan']?.toString() ?? '',
      tenants: int.tryParse(json['tenants']?.toString() ?? '') ?? 0,
      estimatedMrrCents:
          int.tryParse(json['estimated_mrr_cents']?.toString() ?? '') ?? 0,
    );
  }
}

class DashboardTopTenantModel {
  DashboardTopTenantModel({
    required this.tenantId,
    required this.tenantName,
    required this.plan,
    required this.status,
    required this.usedMessages,
    required this.monthlyMessageLimit,
  });

  final String tenantId;
  final String tenantName;
  final String plan;
  final String status;
  final int usedMessages;
  final int monthlyMessageLimit;

  factory DashboardTopTenantModel.fromJson(Map<String, dynamic> json) {
    return DashboardTopTenantModel(
      tenantId: json['tenant_id']?.toString() ?? '',
      tenantName: json['tenant_name']?.toString() ?? '',
      plan: json['plan']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      usedMessages: int.tryParse(json['used_messages']?.toString() ?? '') ?? 0,
      monthlyMessageLimit:
          int.tryParse(json['monthly_message_limit']?.toString() ?? '') ?? 0,
    );
  }
}

class DashboardRecentEventModel {
  DashboardRecentEventModel({
    required this.action,
    required this.summary,
    required this.tenantId,
    this.actorEmail,
    this.createdAt,
  });

  final String action;
  final String summary;
  final String tenantId;
  final String? actorEmail;
  final DateTime? createdAt;

  factory DashboardRecentEventModel.fromJson(Map<String, dynamic> json) {
    return DashboardRecentEventModel(
      action: json['action']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      actorEmail: json['actor_email']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class DashboardOverviewModel {
  DashboardOverviewModel({
    required this.scope,
    this.tenantId,
    this.tenantName,
    required this.kpis,
    required this.planBreakdown,
    required this.topTenants,
    required this.recentEvents,
  });

  final String scope;
  final String? tenantId;
  final String? tenantName;
  final List<DashboardKpiModel> kpis;
  final List<DashboardPlanBreakdownModel> planBreakdown;
  final List<DashboardTopTenantModel> topTenants;
  final List<DashboardRecentEventModel> recentEvents;

  factory DashboardOverviewModel.fromJson(Map<String, dynamic> json) {
    return DashboardOverviewModel(
      scope: json['scope']?.toString() ?? 'tenant',
      tenantId: json['tenant_id']?.toString(),
      tenantName: json['tenant_name']?.toString(),
      kpis: ((json['kpis'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) =>
              DashboardKpiModel.fromJson(item.cast<String, dynamic>()))
          .toList(),
      planBreakdown: ((json['plan_breakdown'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => DashboardPlanBreakdownModel.fromJson(
              item.cast<String, dynamic>()))
          .toList(),
      topTenants: ((json['top_tenants'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) =>
              DashboardTopTenantModel.fromJson(item.cast<String, dynamic>()))
          .toList(),
      recentEvents: ((json['recent_events'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => DashboardRecentEventModel.fromJson(
              item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

