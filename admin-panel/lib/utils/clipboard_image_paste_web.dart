import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

typedef ClipboardImageCallback = void Function(
  Uint8List bytes,
  String mimeType,
  String filename,
);

StreamSubscription<html.ClipboardEvent>? _pasteSub;

void registerClipboardImagePaste({
  required ClipboardImageCallback onImage,
  required bool Function() enabled,
}) {
  unregisterClipboardImagePaste();
  _pasteSub = html.document.onPaste.listen((html.ClipboardEvent event) {
    if (!enabled()) return;
    final data = event.clipboardData;
    if (data == null) return;
    final items = data.items;
    if (items == null) return;

    final itemList = <html.DataTransferItem>[];
    for (var i = 0; i < (items.length ?? 0); i++) {
      final item = items[i];
      if (item != null) itemList.add(item);
    }
    for (final item in itemList) {
      final kind = item.type ?? '';
      if (kind.isEmpty || !kind.startsWith('image/')) continue;

      event.preventDefault();
      event.stopPropagation();

      final file = item.getAsFile();
      if (file == null) continue;

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        final raw = reader.result;
        Uint8List? bytes;
        if (raw is ByteBuffer) {
          bytes = Uint8List.view(raw);
        } else if (raw is Uint8List) {
          bytes = raw;
        }
        if (bytes == null || bytes.isEmpty) return;

        final ext = _extForMime(kind);
        final baseName = file.name.trim();
        final filename = baseName.isNotEmpty
            ? baseName
            : 'colar-${DateTime.now().millisecondsSinceEpoch}.$ext';
        onImage(bytes, kind, filename);
      });
      return;
    }
  });
}

void unregisterClipboardImagePaste() {
  _pasteSub?.cancel();
  _pasteSub = null;
}

String _extForMime(String mime) {
  switch (mime) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/gif':
      return 'gif';
    case 'image/webp':
      return 'webp';
    default:
      return 'png';
  }
}