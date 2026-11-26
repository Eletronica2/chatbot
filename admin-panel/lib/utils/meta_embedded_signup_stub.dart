class MetaEmbeddedSignupResult {
  const MetaEmbeddedSignupResult({
    required this.code,
    this.wabaId,
    this.messagingAccountId,
    this.messagingAccountIds = const <String>[],
    this.phoneNumberId,
    this.displayPhoneNumber,
    this.businessId,
    this.isOnBizApp,
  });

  final String code;
  final String? wabaId;
  final String? messagingAccountId;
  final List<String> messagingAccountIds;
  final String? phoneNumberId;
  final String? displayPhoneNumber;
  final String? businessId;
  final bool? isOnBizApp;
}

Future<MetaEmbeddedSignupResult?> launchMetaEmbeddedSignup({
  required String appId,
  required String configId,
  bool coexistence = true,
  Map<String, dynamic>? extras,
}) async {
  return null;
}

bool get isMetaEmbeddedSignupSupported => false;
