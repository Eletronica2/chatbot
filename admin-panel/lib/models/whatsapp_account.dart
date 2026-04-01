class WhatsAppAccountModel {
  WhatsAppAccountModel({
    required this.accountId,
    required this.tenantId,
    required this.accountKey,
    required this.displayName,
    required this.phoneNumberId,
    required this.displayPhoneNumber,
    required this.status,
    required this.isDefault,
    required this.hasAccessToken,
    this.maskedAccessToken,
    this.verifyToken,
  });

  final String accountId;
  final String tenantId;
  final String accountKey;
  final String displayName;
  final String phoneNumberId;
  final String displayPhoneNumber;
  final String status;
  final bool isDefault;
  final bool hasAccessToken;
  final String? maskedAccessToken;
  final String? verifyToken;

  factory WhatsAppAccountModel.fromJson(Map<String, dynamic> json) {
    return WhatsAppAccountModel(
      accountId: json['account_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      accountKey: json['account_key']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      phoneNumberId: json['phone_number_id']?.toString() ?? '',
      displayPhoneNumber: json['display_phone_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      isDefault: json['is_default'] == true,
      hasAccessToken: json['has_access_token'] == true,
      maskedAccessToken: json['masked_access_token']?.toString(),
      verifyToken: json['verify_token']?.toString(),
    );
  }
}

