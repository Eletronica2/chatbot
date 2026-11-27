import 'package:intl/intl.dart';

const kCampaignMetaDisclaimer =
    'Mensagens cobradas diretamente pela Meta. Os valores apresentados são estimativas.';

final NumberFormat _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final NumberFormat _pctBr = NumberFormat('#,##0.0', 'pt_BR');

String formatCampaignMoney(dynamic raw, {String? currency}) {
  if (raw == null) return '—';
  final value = switch (raw) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s.replaceAll(',', '.')) ?? 0,
    _ => 0.0,
  };
  if (currency != null && currency.toUpperCase() != 'BRL') {
    return '$currency ${value.toStringAsFixed(2)} (est.)';
  }
  return '${_brl.format(value)} (est.)';
}

String formatCampaignMetaEstimate(Map<String, dynamic>? estimate) {
  if (estimate == null || estimate.isEmpty) return '—';
  return formatCampaignMoney(
    estimate['total_if_all_delivered_estimate'],
    currency: estimate['currency']?.toString(),
  );
}

String campaignStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'draft':
      return 'Rascunho';
    case 'validated':
      return 'Validada';
    case 'running':
      return 'Em execução';
    case 'paused':
      return 'Pausada';
    case 'completed':
      return 'Concluída';
    case 'cancelled':
    case 'canceled':
      return 'Cancelada';
    default:
      return status;
  }
}

String recipientStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return 'Pendente';
    case 'sending':
      return 'Enviando';
    case 'sent':
      return 'Enviada';
    case 'delivered':
      return 'Entregue';
    case 'read':
      return 'Lida';
    case 'failed':
      return 'Falhou';
    case 'uncertain':
      return 'Incerta';
    default:
      return status;
  }
}

String formatCampaignDate(DateTime? dt) {
  if (dt == null) return '—';
  try {
    return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(dt.toLocal());
  } catch (_) {
    return '—';
  }
}

String formatCampaignPercent(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return '—';
  return '${_pctBr.format(value)}%';
}