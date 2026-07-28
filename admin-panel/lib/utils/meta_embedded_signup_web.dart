import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

  void handlePayload(JSAny? payload) {
    if (completer.isCompleted) {
      return;
    }
    if (payload == null) {
      completer.complete(null);
      return;
    }

    final map = payload.dartify();
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
  }

  globalContext[callbackName] = handlePayload.toJS;

  final bridge = globalContext.getProperty('MetaSignupBridge'.toJS);
  if (bridge == null) {
    throw StateError(
      'MetaSignupBridge nao carregado. Verifique web/meta_signup_bridge.js em index.html '
      'e reinicie o Flutter Web (hot restart nao recarrega o JS).',
    );
  }

  final bridgeObj = bridge as JSObject;
  final launchFn = bridgeObj.getProperty('launch'.toJS);
  if (launchFn == null) {
    throw StateError('MetaSignupBridge.launch ausente em meta_signup_bridge.js');
  }

  bridgeObj.callMethodVarArgs('launch'.toJS, <JSAny?>[
    appId.toJS,
    configId.toJS,
    coexistence.toJS,
    callbackName.toJS,
    extras?.jsify(),
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
