class TenantUserModel {
  TenantUserModel({
    required this.userId,
    required this.tenantId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    this.createdAt,
    this.lastLoginAt,
  });

  final String userId;
  final String tenantId;
  final String email;
  final String displayName;
  final String role;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory TenantUserModel.fromJson(Map<String, dynamic> json) {
    return TenantUserModel(
      userId: json['user_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'owner',
      status: json['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      lastLoginAt: DateTime.tryParse(json['last_login_at']?.toString() ?? ''),
    );
  }
}

class TenantUserActionTokenModel {
  TenantUserActionTokenModel({
    required this.tokenType,
    required this.token,
    required this.expiresAt,
    required this.actionUrl,
    required this.user,
    this.emailStatus,
    this.emailError,
  });

  final String tokenType;
  final String token;
  final DateTime? expiresAt;
  final String actionUrl;
  final TenantUserModel user;
  final String? emailStatus;
  final String? emailError;

  factory TenantUserActionTokenModel.fromJson(Map<String, dynamic> json) {
    return TenantUserActionTokenModel(
      tokenType: json['token_type']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      actionUrl: json['action_url']?.toString() ?? '',
      emailStatus: json['email_status']?.toString(),
      emailError: json['email_error']?.toString(),
      user: TenantUserModel.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}
