import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as js_util;

import 'meta_embedded_signup_stub.dart';

bool get isMetaEmbeddedSignupSupported => true;

Future<MetaEmbeddedSignupResult?> launchMetaEmbeddedSignup({
  required String appId,
  required String configId,
  bool coexistence = true,
  Map<String, dynamic>? extras,
}) async {
  final completer = Completer<MetaEmbeddedSignupResult?>();
  final callbackName = '_metaSignupCallback_${DateTime.now().millisecondsSinceEpoch}';

  js.context[callbackName] = js.allowInterop((dynamic payload) {
    if (completer.isCompleted) {
      return;
    }
    if (payload == null) {
      completer.complete(null);
      return;
    }
    final map = js_util.dartify(payload);
    if (map is! Map) {
      completer.complete(null);
      return;
    }

    final code = map['code']?.toString() ?? '';
    final wabaId = map['waba_id']?.toString();
    final phoneNumberId = map['phone_number_id']?.toString();

    if (code.isEmpty || wabaId == null || wabaId.isEmpty || phoneNumberId == null || phoneNumberId.isEmpty) {
      completer.complete(null);
      return;
    }

    completer.complete(
      MetaEmbeddedSignupResult(
        code: code,
        wabaId: wabaId,
        phoneNumberId: phoneNumberId,
        displayPhoneNumber: map['display_phone_number']?.toString(),
      ),
    );
  });

  final bridge = js.context['MetaSignupBridge'];
  if (bridge is! js.JsObject) {
    throw StateError(
      'MetaSignupBridge nao carregado. Verifique web/meta_signup_bridge.js em index.html '
      'e reinicie o Flutter Web (hot restart nao recarrega o JS).',
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
    extras != null ? js_util.jsify(extras) : null,
  ]);

  return completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      throw StateError(
        'Tempo esgotado aguardando a Meta. '
        'Complete o codigo de verificacao no celular e tente novamente.',
      );
    },
  );
}
