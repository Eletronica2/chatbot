import 'package:flutter/material.dart';

import '../models/whatsapp_template.dart';
import '../widgets/whatsapp_template_phone_preview.dart';

/// Monta [TemplatePhonePreviewData] a partir de template Meta + valores de variáveis.
class TemplatePreviewMapper {
  static const placeholder = '⟨exemplo⟩';

  static TemplatePhonePreviewData fromTemplate({
    required WhatsAppTemplateModel template,
    required String businessName,
    required List<String> bodyParameterValues,
  }) {
    String resolve(String text) {
      var out = text;
      out = out.replaceAllMapped(RegExp(r'\{\{(\d+)\}\}'), (match) {
        final idx = (int.tryParse(match.group(1) ?? '') ?? 0) - 1;
        if (idx < 0) return match.group(0) ?? '';
        if (idx < bodyParameterValues.length) {
          final v = bodyParameterValues[idx].trim();
          if (v.isNotEmpty) return v;
        }
        if (idx < template.bodyExamples.length) {
          return template.bodyExamples[idx];
        }
        return placeholder;
      });
      return out;
    }

    final headerFormat = template.headerFormat;
    final hasTextHeader =
        headerFormat != null && headerFormat.toUpperCase() == 'TEXT' && (template.headerText ?? '').trim().isNotEmpty;

    final previewButtons = template.buttons
        .map((b) => TemplatePreviewButton(type: b.type, label: b.text))
        .toList();

    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return TemplatePhonePreviewData(
      businessName: businessName,
      headerFormat: hasTextHeader ? 'TEXT' : 'NONE',
      headerText: hasTextHeader ? resolve(template.headerText!.trim()) : '',
      bodyResolved: resolve(template.bodyText ?? ''),
      footerText: resolve(template.footerText ?? ''),
      buttons: previewButtons,
      timeLabel: time,
    );
  }
}