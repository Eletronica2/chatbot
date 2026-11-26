import 'dart:typed_data';

typedef ClipboardImageCallback = void Function(
  Uint8List bytes,
  String mimeType,
  String filename,
);

void registerClipboardImagePaste({
  required ClipboardImageCallback onImage,
  required bool Function() enabled,
}) {}

void unregisterClipboardImagePaste() {}