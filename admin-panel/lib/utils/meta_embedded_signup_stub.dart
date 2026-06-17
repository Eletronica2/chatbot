class MetaEmbeddedSignupResult {
  const MetaEmbeddedSignupResult({
    required this.code,
    this.wabaId,
    this.phoneNumberId,
    this.displayPhoneNumber,
  });

  final String code;
  final String? wabaId;
  final String? phoneNumberId;
  final String? displayPhoneNumber;
}

Future<MetaEmbeddedSignupResult?> launchMetaEmbeddedSignup({
  required String appId,
  required String configId,
  bool coexistence = true,
}) async {
  return null;
}

bool get isMetaEmbeddedSignupSupported => false;
