class SubscriptionInfo {
  SubscriptionInfo({
    required this.tenantId,
    required this.plan,
    required this.status,
    required this.renewalDate,
    required this.monthlyMessageLimit,
    required this.active,
    required this.usedMessages,
    required this.remainingMessages,
  });

  final String tenantId;
  final String plan;
  final String status;
  final DateTime? renewalDate;
  final int monthlyMessageLimit;
  final bool active;
  final int usedMessages;
  final int remainingMessages;

  double get usagePercent {
    if (monthlyMessageLimit <= 0) return 0;
    final ratio = usedMessages / monthlyMessageLimit;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? renewalDate;
    final renewalRaw = json['renewal_date']?.toString();
    if (renewalRaw != null && renewalRaw.isNotEmpty) {
      renewalDate = DateTime.tryParse(renewalRaw);
    }

    return SubscriptionInfo(
      tenantId: json['tenant_id']?.toString() ?? 'default',
      plan: json['plan']?.toString() ?? 'starter',
      status: json['status']?.toString() ?? 'active',
      renewalDate: renewalDate,
      monthlyMessageLimit: int.tryParse(json['monthly_message_limit']?.toString() ?? '') ?? 0,
      active: json['active'] == true,
      usedMessages: int.tryParse(json['used_messages']?.toString() ?? '') ?? 0,
      remainingMessages: int.tryParse(json['remaining_messages']?.toString() ?? '') ?? 0,
    );
  }
}
