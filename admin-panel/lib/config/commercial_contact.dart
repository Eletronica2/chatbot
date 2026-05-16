/// Contato comercial da landing e CTAs "Falar no WhatsApp".
///
/// Substitua pelo número real em formato internacional, apenas dígitos (ex.: 5511987654321).
const String kCommercialWhatsAppE164 = '5511999999999';

/// Retorna true quando o número parece configurado (não é o placeholder genérico).
bool get isCommercialWhatsAppConfigured {
  final d = kCommercialWhatsAppE164.replaceAll(RegExp(r'\D'), '');
  if (d.length < 10) return false;
  // Placeholder típico do template — altere para seu número real.
  if (d == '5511999999999') return false;
  return true;
}

/// URI https://wa.me/… com texto opcional pré-preenchido.
Uri commercialWhatsAppUri({String? prefilledMessage}) {
  final digits = kCommercialWhatsAppE164.replaceAll(RegExp(r'\D'), '');
  final base = Uri.parse('https://wa.me/$digits');
  if (prefilledMessage == null || prefilledMessage.trim().isEmpty) {
    return base;
  }
  return base.replace(queryParameters: {'text': prefilledMessage.trim()});
}
