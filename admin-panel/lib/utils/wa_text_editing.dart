import 'package:flutter/material.dart';

class WaTextEditing {
  static void insertAtSelection(TextEditingController controller, String chunk) {
    final sel = controller.selection;
    final text = controller.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, chunk);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + chunk.length),
    );
  }

  static void toggleWrap(TextEditingController controller, String left, String right) {
    final sel = controller.selection;
    final text = controller.text;
    if (!sel.isValid) return;
  final start = sel.start;
  final end = sel.end;
    if (start < 0 || end < 0) return;

    if (!sel.isCollapsed) {
      var segment = text.substring(start, end);
      if (segment.startsWith(left) && segment.endsWith(right) && segment.length >= left.length + right.length) {
        segment = segment.substring(left.length, segment.length - right.length);
        final next = text.replaceRange(start, end, segment);
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection(baseOffset: start, extentOffset: start + segment.length),
        );
        return;
      }
      final wrapped = '$left$segment$right';
      final next = text.replaceRange(start, end, wrapped);
      controller.value = TextEditingValue(
        text: next,
        selection: TextSelection(baseOffset: start, extentOffset: start + wrapped.length),
      );
      return;
    }

    final wrapped = '$left$right';
    final next = text.replaceRange(start, end, wrapped);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + left.length),
    );
  }

  static void insertVariable(TextEditingController controller) {
    final text = controller.text;
    final matches = RegExp(r'\{\{(\d+)\}\}').allMatches(text);
    var max = 0;
    for (final m in matches) {
      final n = int.tryParse(m.group(1) ?? '') ?? 0;
      if (n > max) max = n;
    }
    insertAtSelection(controller, '{{${max + 1}}}');
  }
}