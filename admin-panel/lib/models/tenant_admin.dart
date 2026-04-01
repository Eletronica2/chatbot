class TenantAdminSummary {
  TenantAdminSummary({
    required this.tenantId,
    required this.name,
    required this.email,
    required this.status,
    required this.plan,
    this.ownerEmail,
    this.createdAt,
    this.updatedAt,
  });

  final String tenantId;
  final String name;
  final String email;
  final String status;
  final String plan;
  final String? ownerEmail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TenantAdminSummary.fromJson(Map<String, dynamic> json) {
    return TenantAdminSummary(
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      plan: json['plan']?.toString() ?? 'starter',
      ownerEmail: json['owner_email']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
