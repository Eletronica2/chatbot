import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Dados para gerar proposta comercial em PDF (estrutura narrativa premium).
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
    this.documentTitle,
    this.introductionText,
    this.implementationExplainer,
    this.subscriptionExplainer,
    this.benefitLines,
    this.timelineText,
    this.closingText,
    this.approveLabel,
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

  /// Quando omitido, usa título padrão orientado a valor (sem “chatbot”).
  final String? documentTitle;

  final String? introductionText;
  final String? implementationExplainer;
  final String? subscriptionExplainer;
  final List<String>? benefitLines;
  final String? timelineText;
  final String? closingText;
  final String? approveLabel;
}

const _kDefaultDocumentTitle = 'Proposta Comercial — Atendimento Inteligente com IA';

const _kDefaultIntroduction =
    'Esta proposta apresenta uma solução de atendimento inteligente com IA para WhatsApp '
    'oficial, combinando automação contextual com experiência humanizada. O objetivo é '
    'reduzir tempo de resposta, organizar conversas e aumentar conversão, mantendo sua '
    'equipe no controle quando necessário.';

const _kDefaultImplementationExplainer =
    'A implantação corresponde à configuração inicial completa do sistema para o seu negócio. '
    'Inclui criação dos fluxos de conversa, treinamento da IA no tom da marca, testes '
    'com cenários reais, ativação e ajustes finos antes do go-live.';

const _kDefaultSubscriptionExplainer =
    'A mensalidade garante acesso contínuo à plataforma, IA, infraestrutura, atualizações '
    'e suporte conforme o plano contratado.';

const _kDefaultTimeline = 'Prazo médio de implantação: 3 a 7 dias úteis.';

const _kDefaultClosing =
    'Estamos prontos para transformar seu WhatsApp em um canal inteligente de atendimento e vendas. '
    'Qualquer dúvida, nossa equipe comercial está à disposição.';

const _kDefaultApprove = 'Aprovar proposta';

const _kIncludedBaseline = [
  'Configuração do WhatsApp oficial (Cloud API)',
  'Automação inteligente de conversas',
  'IA contextual no fluxo de atendimento',
  'Painel administrativo para sua equipe',
  'Treinamento inicial da equipe',
  'Suporte inicial à operação',
];

const _kDefaultBenefits = [
  'Atendimento contínuo com respostas rápidas',
  'Respostas automáticas inteligentes e contextuais',
  'Redução do tempo médio de atendimento',
  'Melhor experiência para seus clientes',
  'Organização das conversas em um só lugar',
  'Escalabilidade operacional para crescer',
];

List<String> _mergedIncludedItems(ProposalPdfData data) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in [..._kIncludedBaseline, ...data.includedItems]) {
    final t = raw.trim();
    if (t.isEmpty || seen.contains(t)) continue;
    seen.add(t);
    out.add(t);
  }
  return out;
}

pw.Widget _sectionTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8, top: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
    ),
  );
}

pw.Widget _bodyParagraph(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, lineSpacing: 1.35, color: PdfColors.grey800),
    ),
  );
}

pw.Widget _bulletLine(String line) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 5,
          height: 5,
          margin: const pw.EdgeInsets.only(top: 3.5, right: 8),
          decoration: const pw.BoxDecoration(color: PdfColors.deepOrange800, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(
          child: pw.Text(line, style: pw.TextStyle(fontSize: 10, lineSpacing: 1.35)),
        ),
      ],
    ),
  );
}

pw.Widget _kvSimple(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 4,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ),
  );
}

Future<Uint8List> buildProposalPdf(ProposalPdfData data) async {
  final currency = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dateStr = DateFormat('dd/MM/yyyy').format(data.issueDate ?? DateTime.now());
  final docTitle = (data.documentTitle ?? _kDefaultDocumentTitle).trim();
  final intro = (data.introductionText ?? _kDefaultIntroduction).trim();
  final implExpl = (data.implementationExplainer ?? _kDefaultImplementationExplainer).trim();
  final subExpl = (data.subscriptionExplainer ?? _kDefaultSubscriptionExplainer).trim();
  final timeline = (data.timelineText ?? _kDefaultTimeline).trim();
  final closing = (data.closingText ?? _kDefaultClosing).trim();
  final approve = (data.approveLabel ?? _kDefaultApprove).trim();
  final benefits = data.benefitLines != null && data.benefitLines!.isNotEmpty
      ? data.benefitLines!
      : _kDefaultBenefits;
  final mergedIncluded = _mergedIncludedItems(data);

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      margin: const pw.EdgeInsets.all(44),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(22),
          decoration: pw.BoxDecoration(
            gradient: const pw.LinearGradient(
              colors: [PdfColor.fromInt(0xFF0F172A), PdfColor.fromInt(0xFF1E293B)],
            ),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Operada',
                style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                docTitle,
                style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Emitida em $dateStr',
                style: pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 26),
        pw.Text(
          data.companyName,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${data.contactName}\n${data.contactEmail}'
          '${data.contactWhatsapp != null && data.contactWhatsapp!.trim().isNotEmpty ? '\nWhatsApp: ${data.contactWhatsapp}' : ''}',
          style: pw.TextStyle(fontSize: 10, lineSpacing: 1.4, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 18),
        _sectionTitle('Introdução'),
        _bodyParagraph(intro),
        _sectionTitle('O que está incluso'),
        ...mergedIncluded.map(_bulletLine),
        pw.SizedBox(height: 8),
        _sectionTitle('Implantação'),
        _bodyParagraph(implExpl),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Investimento único — implantação',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                currency.format(data.setupFee),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              _bulletLine('Criação dos fluxos personalizados'),
              _bulletLine('Treinamento e calibragem da IA'),
              _bulletLine('Testes completos antes da publicação'),
              _bulletLine('Ativação e ajustes iniciais'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        _sectionTitle('Mensalidade'),
        pw.Text(
          'Plano contratado: ${data.planLabel}',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${currency.format(data.monthlyValue)} / mês',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
        ),
        pw.SizedBox(height: 8),
        _bodyParagraph(subExpl),
        _kvSimple('Limite de mensagens (referência mensal)', '${data.monthlyMessageLimit}'),
        _kvSimple('Validade desta proposta', '${data.validityDays} dias'),
        pw.SizedBox(height: 8),
        _sectionTitle('Benefícios'),
        ...benefits.map(_bulletLine),
        pw.SizedBox(height: 8),
        _sectionTitle('Prazo de implantação'),
        _bodyParagraph(timeline),
        if (data.notes != null && data.notes!.trim().isNotEmpty) ...[
          _sectionTitle('Observações'),
          _bodyParagraph(data.notes!.trim()),
        ],
        pw.SizedBox(height: 12),
        _sectionTitle('Encerramento'),
        _bodyParagraph(closing),
        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: pw.BoxDecoration(
            gradient: const pw.LinearGradient(
              colors: [PdfColor.fromInt(0xFFEA580C), PdfColor.fromInt(0xFFFB923C)],
            ),
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Center(
            child: pw.Text(
              approve,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 32),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 14),
        pw.Text(
          'Referência técnica do plano: ${data.planKey}. Valores válidos conforme validade da proposta.',
          style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700, lineSpacing: 1.25),
        ),
        pw.SizedBox(height: 20),
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
