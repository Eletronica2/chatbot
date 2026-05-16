import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Dados suficientes para gerar uma proposta comercial em PDF (sem depender do backend gravar primeiro).
class ProposalPdfData {
  ProposalPdfData({
    required this.companyName,
    required this.contactName,
    required this.contactEmail,
    this.contactWhatsapp,
    required this.planLabel,
    required this.planKey,
    required this.monthlyValue,
    required this.setupFee,
    required this.monthlyMessageLimit,
    required this.includedItems,
    required this.validityDays,
    this.notes,
    this.issueDate,
  });

  final String companyName;
  final String contactName;
  final String contactEmail;
  final String? contactWhatsapp;
  final String planLabel;
  final String planKey;
  final double monthlyValue;
  final double setupFee;
  final int monthlyMessageLimit;
  final List<String> includedItems;
  final int validityDays;
  final String? notes;
  final DateTime? issueDate;
}

Future<Uint8List> buildProposalPdf(ProposalPdfData data) async {
  final currency = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dateStr = DateFormat("dd/MM/yyyy").format(data.issueDate ?? DateTime.now());

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            gradient: const pw.LinearGradient(
              colors: [PdfColor.fromInt(0xFF0F172A), PdfColor.fromInt(0xFF1E293B)],
            ),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Operada',
                style: pw.TextStyle(color: PdfColors.white, fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Proposta comercial • WhatsApp inteligente',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 28),
        pw.Text('Proposta de serviços', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Emitida em $dateStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 20),
        pw.Text('Cliente', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text(data.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${data.contactName}\n${data.contactEmail}'
          '${data.contactWhatsapp != null && data.contactWhatsapp!.isNotEmpty ? '\nWhatsApp: ${data.contactWhatsapp}' : ''}',
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Plano recomendado', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('${data.planLabel} (${data.planKey})',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              _row('Mensalidade sugerida', currency.format(data.monthlyValue)),
              _row('Investimento inicial (implantação, treino e WhatsApp)',
                  currency.format(data.setupFee)),
              _row('Limite de mensagens / mês', '${data.monthlyMessageLimit}'),
              _row('Validade da proposta', '${data.validityDays} dias'),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text('O que está incluído',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...data.includedItems.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  margin: const pw.EdgeInsets.only(top: 3, right: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.orange, shape: pw.BoxShape.circle),
                ),
                pw.Expanded(
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.3)),
                ),
              ],
            ),
          ),
        ),
        if (data.notes != null && data.notes!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Observações', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(data.notes!, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.3)),
        ],
        pw.SizedBox(height: 36),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 12),
        pw.Text(
          'A mensalidade cobre uso da plataforma; o valor de implantação cobre '
          'configuração do WhatsApp Cloud API, treinamento da equipe na automação e go-live supervisionado.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700, lineSpacing: 1.3),
        ),
        pw.SizedBox(height: 24),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(children: [
              pw.Container(height: 1, width: 160, color: PdfColors.black),
              pw.SizedBox(height: 6),
              pw.Text('Assinatura do cliente', style: pw.TextStyle(fontSize: 9)),
            ]),
            pw.Column(children: [
              pw.Container(height: 1, width: 160, color: PdfColors.black),
              pw.SizedBox(height: 6),
              pw.Text('Operada • Comercial', style: pw.TextStyle(fontSize: 9)),
            ]),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _row(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        ),
        pw.Expanded(
          flex: 2,
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ),
  );
}
