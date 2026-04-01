class AppUser {
  AppUser({
    required this.userId,
    required this.tenantId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.accessToken,
  });

  final String userId;
  final String tenantId;
  final String email;
  final String displayName;
  final String role;
  final String accessToken;

  factory AppUser.fromUserJson(
    Map<String, dynamic> json, {
    required String accessToken,
  }) {
    return AppUser(
      userId: json['user_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? 'default',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'owner',
      accessToken: accessToken,
    );
  }

  factory AppUser.fromLoginJson(Map<String, dynamic> json) {
    final user = (json['user'] is Map<String, dynamic>)
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AppUser.fromUserJson(
      user,
      accessToken: json['access_token']?.toString() ?? '',
    );
  }

  factory AppUser.fromStorageJson(Map<String, dynamic> json) {
    return AppUser.fromUserJson(
      json,
      accessToken: json['access_token']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toStorageJson() {
    return <String, dynamic>{
      'user_id': userId,
      'tenant_id': tenantId,
      'email': email,
      'display_name': displayName,
      'role': role,
      'access_token': accessToken,
    };
  }
}
