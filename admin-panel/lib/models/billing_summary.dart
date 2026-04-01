class BillingCustomerModel {
  BillingCustomerModel({
    required this.providerCustomerId,
    this.providerSubscriptionId,
    this.providerPriceId,
    required this.status,
    this.currentPeriodEnd,
    this.checkoutUrl,
    this.portalUrl,
  });

  final String providerCustomerId;
  final String? providerSubscriptionId;
  final String? providerPriceId;
  final String status;
  final DateTime? currentPeriodEnd;
  final String? checkoutUrl;
  final String? portalUrl;

  factory BillingCustomerModel.fromJson(Map<String, dynamic> json) {
    return BillingCustomerModel(
      providerCustomerId: json['provider_customer_id']?.toString() ?? '',
      providerSubscriptionId: json['provider_subscription_id']?.toString(),
      providerPriceId: json['provider_price_id']?.toString(),
      status: json['status']?.toString() ?? 'inactive',
      currentPeriodEnd:
          DateTime.tryParse(json['current_period_end']?.toString() ?? ''),
      checkoutUrl: json['checkout_url']?.toString(),
      portalUrl: json['portal_url']?.toString(),
    );
  }
}

class BillingInvoiceModel {
  BillingInvoiceModel({
    required this.providerInvoiceId,
    required this.status,
    required this.amountDue,
    required this.amountPaid,
    required this.currency,
    this.hostedInvoiceUrl,
    this.invoicePdfUrl,
    this.dueDate,
    this.paidAt,
    this.createdAt,
  });

  final String providerInvoiceId;
  final String status;
  final int amountDue;
  final int amountPaid;
  final String currency;
  final String? hostedInvoiceUrl;
  final String? invoicePdfUrl;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory BillingInvoiceModel.fromJson(Map<String, dynamic> json) {
    return BillingInvoiceModel(
      providerInvoiceId: json['provider_invoice_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      amountDue: int.tryParse(json['amount_due']?.toString() ?? '') ?? 0,
      amountPaid: int.tryParse(json['amount_paid']?.toString() ?? '') ?? 0,
      currency: json['currency']?.toString() ?? 'brl',
      hostedInvoiceUrl: json['hosted_invoice_url']?.toString(),
      invoicePdfUrl: json['invoice_pdf_url']?.toString(),
      dueDate: DateTime.tryParse(json['due_date']?.toString() ?? ''),
      paidAt: DateTime.tryParse(json['paid_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class BillingSummaryModel {
  BillingSummaryModel({
    required this.tenantId,
    required this.provider,
    required this.providerReady,
    required this.subscriptionStatus,
    required this.currentPlan,
    required this.monthlyMessageLimit,
    required this.usedMessages,
    required this.remainingMessages,
    required this.graceDays,
    required this.availablePlans,
    this.renewalDate,
    this.customer,
    required this.invoices,
  });

  final String tenantId;
  final String provider;
  final bool providerReady;
  final String subscriptionStatus;
  final String currentPlan;
  final DateTime? renewalDate;
  final int monthlyMessageLimit;
  final int usedMessages;
  final int remainingMessages;
  final int graceDays;
  final BillingCustomerModel? customer;
  final List<BillingInvoiceModel> invoices;
  final List<String> availablePlans;

  factory BillingSummaryModel.fromJson(Map<String, dynamic> json) {
    return BillingSummaryModel(
      tenantId: json['tenant_id']?.toString() ?? 'default',
      provider: json['provider']?.toString() ?? 'stripe',
      providerReady: json['provider_ready'] == true,
      subscriptionStatus: json['subscription_status']?.toString() ?? 'inactive',
      currentPlan: json['current_plan']?.toString() ?? 'starter',
      renewalDate: DateTime.tryParse(json['renewal_date']?.toString() ?? ''),
      monthlyMessageLimit:
          int.tryParse(json['monthly_message_limit']?.toString() ?? '') ?? 0,
      usedMessages: int.tryParse(json['used_messages']?.toString() ?? '') ?? 0,
      remainingMessages:
          int.tryParse(json['remaining_messages']?.toString() ?? '') ?? 0,
      graceDays: int.tryParse(json['grace_days']?.toString() ?? '') ?? 0,
      customer: json['customer'] is Map<String, dynamic>
          ? BillingCustomerModel.fromJson(
              json['customer'] as Map<String, dynamic>)
          : null,
      invoices: ((json['invoices'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) =>
              BillingInvoiceModel.fromJson(item.cast<String, dynamic>()))
          .toList(),
      availablePlans: ((json['available_plans'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

