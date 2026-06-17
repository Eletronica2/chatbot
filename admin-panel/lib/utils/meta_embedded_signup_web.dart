import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

import 'meta_embedded_signup_stub.dart';

bool get isMetaEmbeddedSignupSupported => true;

Future<MetaEmbeddedSignupResult?> launchMetaEmbeddedSignup({
  required String appId,
  required String configId,
  bool coexistence = true,
}) async {
  final completer = Completer<MetaEmbeddedSignupResult?>();
  final callbackName = '_metaSignupCallback_${DateTime.now().millisecondsSinceEpoch}';

  js.context[callbackName] = js.allowInterop((dynamic payload) {
    if (payload == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final map = js_util.dartify(payload);
    if (map is! Map) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final code = map['code']?.toString() ?? '';
    if (code.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    if (!completer.isCompleted) {
      completer.complete(
        MetaEmbeddedSignupResult(
          code: code,
          wabaId: map['waba_id']?.toString(),
          phoneNumberId: map['phone_number_id']?.toString(),
          displayPhoneNumber: map['display_phone_number']?.toString(),
        ),
      );
    }
  });

  final bridge = js.context['MetaSignupBridge'];
  if (bridge is! js.JsObject) {
    throw StateError(
      'MetaSignupBridge nao carregado. Verifique se web/meta_signup_bridge.js '
      'esta em web/index.html e reinicie o Flutter Web (hot restart nao basta).',
    );
  }
  if (!bridge.hasProperty('launch')) {
    throw StateError('MetaSignupBridge.launch ausente em meta_signup_bridge.js');
  }

  bridge.callMethod('launch', [
    appId,
    configId,
    coexistence,
    callbackName,
  ]);

  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () => null,
  );
}
