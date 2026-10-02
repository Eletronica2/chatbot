import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/lead_service.dart';
import '../services/pdf/proposal_pdf.dart';
import '../services/proposal_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

const _kMetaDirectNotice = 'Tarifas da Meta: cobradas diretamente pela Meta conforme uso e categoria.';
const _kPrepaidNotice = 'Campanhas são pré-pagas e o consumo considera mensagens entregues.';

String _suggestTenantId(String companyName) {
  final raw = companyName
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  if (raw.isEmpty) return 'empresa_nova';
  return raw.replaceAll(RegExp(r'_+'), '_');
}

String _brl(double v) {
  final negative = v < 0;
  final fixed = v.abs().toStringAsFixed(2).split('.');
  return '${negative ? '-' : ''}R\$ ${_thousands(fixed[0])},${fixed[1]}';
}

String _brlText(String? raw) {
  final v = double.tryParse(raw ?? '');
  return v == null ? '—' : _brl(v);
}

String _thousands(String digits) => digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

double _parseMoney(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
  final normalized = s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s;
  return double.tryParse(normalized) ?? 0;
}

int _parseInt(String raw) => int.tryParse(raw.trim().replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

String _moneyField(double? v) => v == null ? '' : v.toStringAsFixed(2).replaceAll('.', ',');

Color _marginColor(String status) {
  switch (status) {
    case 'red':
      return AppColors.danger;
    case 'yellow':
      return AppColors.warning;
    case 'green':
      return AppColors.success;
    default:
      return const Color(0xFF98A4C0);
  }
}

const _kComponentLabels = {
  'meta': 'custo Meta',
  'ai': 'custo de IA',
  'payment': 'taxa de pagamento',
  'tax': 'impostos',
};

Future<void> showLeadProposalDialog(
  BuildContext context,
  Lead lead, {
  required VoidCallback onChanged,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => _ProposalDialogShell(lead: lead, onSaved: onChanged),
  );
}

Future<void> showConvertLeadDialog(
  BuildContext context,
  Lead lead, {
  required VoidCallback onConverted,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => _ConvertLeadShell(
      lead: lead,
      onConverted: onConverted,
    ),
  );
}

class _BillingModeSelector extends StatelessWidget {
  const _BillingModeSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in const [kBillingModeCustomerDirect, kBillingModeSolutionPartner])
          ChoiceChip(
            label: Text(billingModeLabel(mode)),
            selected: value == mode,
            onSelected: onChanged == null ? null : (_) => onChanged!(mode),
          ),
      ],
    );
  }
}

/// --- Proposal dialog (Catálogo V2) ---
class _ProposalDialogShell extends StatefulWidget {
  const _ProposalDialogShell({required this.lead, required this.onSaved});

  final Lead lead;
  final VoidCallback onSaved;

  @override
  State<_ProposalDialogShell> createState() => _ProposalDialogShellState();
}

class _ProposalDialogShellState extends State<_ProposalDialogShell> {
  bool _loading = true;
  PlanRecommendation? _rec;
  List<CatalogPlanOption> _plans = const [];
  String? _error;

  String? _planCode;
  String _billingMode = kBillingModeCustomerDirect;

  late final TextEditingController _monthly;
  late final TextEditingController _setup;
  late final TextEditingController _limit;
  late final TextEditingController _validity;
  late final TextEditingController _items;
  late final TextEditingController _notes;
  late final TextEditingController _overrideReason;

  MarginCheck? _margin;
  bool _marginLoading = false;
  String? _marginError;
  Timer? _marginDebounce;
  int _marginSeq = 0;

  bool _savingSent = false;

  @override
  void initState() {
    super.initState();
    _monthly = TextEditingController();
    _setup = TextEditingController();
    _limit = TextEditingController();
    _validity = TextEditingController(text: '7');
    _items = TextEditingController();
    _notes = TextEditingController();
    _overrideReason = TextEditingController();
    _monthly.addListener(_scheduleMarginCheck);
    _limit.addListener(_scheduleMarginCheck);
    _bootstrap();
  }

  CatalogPlanOption? get _selectedPlan {
    for (final p in _plans) {
      if (p.code == _planCode) return p;
    }
    return null;
  }

  Future<void> _bootstrap({String? billingMode}) async {
    final rid = int.tryParse(widget.lead.id);
    if (rid == null) {
      setState(() {
        _loading = false;
        _error = 'ID de lead inválido.';
      });
      return;
    }
    try {
      final results = await Future.wait([
        proposalApiService.recommendationForLead(rid, billingMode: billingMode),
        if (_plans.isEmpty) proposalApiService.catalogPlans(),
      ]);
      if (!mounted) return;
      final rec = results[0] as PlanRecommendation;
      setState(() {
        if (results.length > 1) {
          _plans = (results[1] as List<CatalogPlanOption>).where((p) => p.isActive).toList(growable: false);
        }
        _rec = rec;
        _billingMode = rec.billingMode;
        _items.text = rec.includedItems.join('\n');
        if (billingMode == null) {
          _planCode = rec.planCode;
          _monthly.text = _moneyField(rec.monthlyValue);
          _setup.text = _moneyField(rec.setupFee);
          _limit.text = rec.monthlyMessageLimit == null ? '' : '${rec.monthlyMessageLimit}';
        }
        _loading = false;
        _error = null;
      });
      _scheduleMarginCheck(immediate: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar recomendação: ${apiErrorText(e)}';
      });
    }
  }

  @override
  void dispose() {
    _marginDebounce?.cancel();
    _monthly.dispose();
    _setup.dispose();
    _limit.dispose();
    _validity.dispose();
    _items.dispose();
    _notes.dispose();
    _overrideReason.dispose();
    super.dispose();
  }

  List<String> _parseItems(String raw) =>
      raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(growable: false);

  void _scheduleMarginCheck({bool immediate = false}) {
    _marginDebounce?.cancel();
    _marginDebounce = Timer(Duration(milliseconds: immediate ? 0 : 450), _runMarginCheck);
  }

  Future<void> _runMarginCheck() async {
    final price = _parseMoney(_monthly.text);
    final units = _parseInt(_limit.text);
    if (price <= 0 || units <= 0) {
      if (mounted) {
        setState(() {
          _margin = null;
          _marginError = 'Informe mensalidade e franquia para validar a margem.';
        });
      }
      return;
    }
    final seq = ++_marginSeq;
    setState(() => _marginLoading = true);
    try {
      final margin = await proposalApiService.marginCheck(
        planCode: _planCode,
        price: price,
        operationalUnits: units,
        billingMode: _billingMode,
        overrideReason: _overrideReason.text,
      );
      if (!mounted || seq != _marginSeq) return;
      setState(() {
        _margin = margin;
        _marginError = null;
        _marginLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _marginSeq) return;
      setState(() {
        _marginLoading = false;
        _marginError = apiErrorText(e);
      });
    }
  }

  void _selectPlan(CatalogPlanOption plan) {
    setState(() => _planCode = plan.code);
    _monthly.text = _moneyField(plan.price);
    _limit.text = plan.operationalUnits == null ? '' : '${plan.operationalUnits}';
    if (_rec != null && plan.code == _rec!.planCode) {
      _setup.text = _moneyField(_rec!.setupFee);
    }
    final allowance = plan.operationalUnits;
    final lines = _parseItems(_items.text)
        .where((l) => !l.toLowerCase().contains('mensagens operacionais entregues/mês'))
        .toList();
    if (allowance != null) {
      lines.insert(lines.length > 4 ? 4 : lines.length,
          'Até ${_thousands('$allowance')} mensagens operacionais entregues/mês');
    }
    _items.text = lines.join('\n');
    _scheduleMarginCheck(immediate: true);
  }

  void _changeMode(String mode) {
    if (mode == _billingMode) return;
    setState(() => _billingMode = mode);
    _bootstrap(billingMode: mode);
  }

  String? get _marketingLine {
    final rec = _rec;
    if (rec == null || _billingMode != kBillingModeSolutionPartner) return null;
    final volume = rec.marketingVolume ?? 0;
    if (volume <= 0 || rec.marketingEstimate == null) return null;
    return 'Campanhas estimadas: ${_thousands('$volume')} mensagens/mês × '
        '${_brl(rec.marketingUnitPrice ?? 0)} = ${_brl(rec.marketingEstimate!)} (créditos de campanha pré-pagos). '
        '$_kPrepaidNotice';
  }

  bool get _canSave {
    final m = _margin;
    if (_planCode == null || m == null || _marginLoading) return false;
    if (!m.allowed) return false;
    return true;
  }

  Future<void> _saveSent() async {
    final rid = int.tryParse(widget.lead.id);
    final planCode = _planCode;
    if (rid == null || planCode == null) return;
    setState(() => _savingSent = true);
    try {
      await proposalApiService.create(
        leadId: rid,
        companyName: widget.lead.company,
        contactName: widget.lead.name,
        contactEmail: widget.lead.email,
        contactWhatsapp: widget.lead.whatsapp,
        planCode: planCode,
        billingMode: _billingMode,
        monthlyValue: _parseMoney(_monthly.text),
        setupFee: _parseMoney(_setup.text),
        monthlyMessageLimit: _parseInt(_limit.text),
        operationalVolume: _rec?.operationalVolume,
        marketingVolume: _rec?.marketingVolume,
        includedItems: _parseItems(_items.text),
        validityDays: _parseInt(_validity.text).clamp(1, 180),
        status: 'sent',
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        marginOverrideReason: _margin?.requiresReason == true ? _overrideReason.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proposta salva como enviada.')),
      );
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingSent = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorText(e))));
    }
  }

  void _downloadPdf() {
    final plan = _selectedPlan;
    Printing.layoutPdf(
      name: 'proposta_${widget.lead.company}.pdf',
      onLayout: (_) async => buildProposalPdf(
        ProposalPdfData(
          companyName: widget.lead.company,
          contactName: widget.lead.name,
          contactEmail: widget.lead.email,
          contactWhatsapp: widget.lead.whatsapp,
          planLabel: plan?.label ?? _rec?.planLabel ?? '',
          planKey: plan?.code ?? _planCode ?? '',
          monthlyValue: _parseMoney(_monthly.text),
          setupFee: _parseMoney(_setup.text),
          monthlyMessageLimit: _parseInt(_limit.text),
          includedItems: _parseItems(_items.text),
          validityDays: _parseInt(_validity.text).clamp(1, 180),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          billingModeNotice: _billingMode == kBillingModeCustomerDirect ? _kMetaDirectNotice : _kPrepaidNotice,
          marketingLine: _marketingLine,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = _rec;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.cinematic,
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.request_quote_rounded, color: AppColors.primary),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Gerar proposta',
                              style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF98A4C0)),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ],
                      Text(
                        widget.lead.company,
                        style: const TextStyle(color: Color(0xFFF5F7FF), fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.lead.name} • ${widget.lead.email}',
                        style: const TextStyle(color: Color(0xFF98A4C0), fontSize: 12),
                      ),
                      if (rec != null) ...[
                        const SizedBox(height: 12),
                        _infoBox(
                          color: AppColors.primary,
                          lines: [
                            'Atendimento informado: ${rec.operationalAnswer ?? 'não informado'}'
                                ' • Campanhas: ${rec.marketingAnswer ?? 'não informado'}',
                            'Recomendação: ${rec.planLabel} — ${rec.rationale}',
                            if (rec.warning != null) rec.warning!,
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _label('Modo de cobrança Meta'),
                      const SizedBox(height: 8),
                      _BillingModeSelector(value: _billingMode, onChanged: _changeMode),
                      const SizedBox(height: 16),
                      _label('Plano (catálogo ${rec?.catalogVersion ?? 'V2'})'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in _plans)
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(p.isCustom
                                      ? '${p.label} • sob consulta'
                                      : '${p.label} • ${_brl(p.price ?? 0)} • ${_thousands('${p.operationalUnits ?? 0}')}'),
                                  if (rec?.planCode == p.code) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text('Sugerido',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                                    ),
                                  ],
                                ],
                              ),
                              selected: _planCode == p.code,
                              onSelected: (_) => _selectPlan(p),
                            ),
                        ],
                      ),
                      if (_selectedPlan?.isCustom == true) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Plano sob consulta: defina mensalidade e franquia; o Margin Guard valida antes de salvar.',
                          style: TextStyle(color: AppColors.warning, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _field('Mensalidade (R\$)', _monthly)),
                          const SizedBox(width: 12),
                          Expanded(child: _field('Implantação / treino (R\$)', _setup)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _field('Mensagens operacionais entregues / mês', _limit, digits: true)),
                          const SizedBox(width: 12),
                          Expanded(child: _field('Validade (dias)', _validity, digits: true)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _meta(),
                      const SizedBox(height: 10),
                      _marginCard(),
                      if (_margin?.requiresReason == true) ...[
                        const SizedBox(height: 10),
                        _field('Justificativa da margem (obrigatória, registrada em auditoria)', _overrideReason,
                            maxLines: 2, onChanged: (_) => _scheduleMarginCheck()),
                      ],
                      const SizedBox(height: 12),
                      _label('Itens incluídos (1 por linha)'),
                      const SizedBox(height: 6),
                      _textArea(_items, 6),
                      const SizedBox(height: 10),
                      _label('Observações internas'),
                      const SizedBox(height: 6),
                      _textArea(_notes, 2),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: PremiumAccentButton(
                              label: _savingSent ? 'Salvando...' : 'Salvar como enviada',
                              icon: Icons.send_rounded,
                              dense: true,
                              expand: true,
                              onPressed: (_savingSent || !_canSave) ? null : _saveSent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PremiumAccentButton(
                              label: 'Baixar PDF',
                              icon: Icons.picture_as_pdf_rounded,
                              dense: true,
                              expand: true,
                              onPressed: _canSave ? _downloadPdf : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _meta() {
    final marketing = _marketingLine;
    if (_billingMode == kBillingModeCustomerDirect) {
      final estimate = _margin?.metaCustomerEstimate;
      return _infoBox(
        color: const Color(0xFF6E7B99),
        lines: [
          _kMetaDirectNotice,
          if (estimate != null) 'Estimativa de custo Meta pago pelo cliente (pior caso operacional): ${_brlText(estimate)}/mês.',
          'Campanhas: tarifas Meta cobradas diretamente do cliente pela Meta.',
        ],
      );
    }
    return _infoBox(
      color: const Color(0xFF6E7B99),
      lines: [
        'Custo Meta operacional entra no custo da Atende Ai (pior caso do rate card vigente).',
        marketing ?? _kPrepaidNotice,
      ],
    );
  }

  Widget _marginCard() {
    if (_marginLoading && _margin == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final m = _margin;
    if (m == null) {
      return _infoBox(color: AppColors.warning, lines: [_marginError ?? 'Margem ainda não calculada.']);
    }
    final color = _marginColor(m.status);
    final unknown = m.unknownComponents.map((c) => _kComponentLabels[c] ?? c).join(', ');
    final costs = m.costs;
    final lines = <String>[
      'Margem de contribuição: ${m.marginPercent == null ? '—' : '${m.marginPercent}%'} • ${m.statusLabel}',
      'Custos conhecidos: Meta ${_brlText(costs['meta']?.toString())} • IA ${_brlText(costs['ai']?.toString())}'
          ' • Pagamento ${_brlText(costs['payment']?.toString())} • Impostos ${_brlText(costs['tax']?.toString())}',
      if (m.minimumSafePrice != null) 'Preço mínimo para 30% (custos conhecidos): ${_brlText(m.minimumSafePrice)}',
      if (unknown.isNotEmpty) 'Estimativa parcial — configure todos os custos ($unknown).',
      if (!m.allowed || m.requiresReason) m.discountMessage,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                m.status == 'red'
                    ? Icons.block_rounded
                    : (m.status == 'green' ? Icons.verified_rounded : Icons.info_outline_rounded),
                color: color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text('Margin Guard',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
              if (_marginLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lines.where((l) => l.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(l, style: const TextStyle(color: AppColors.text, fontSize: 12, height: 1.35)),
            ),
        ],
      ),
    );
  }

  Widget _infoBox({required Color color, required List<String> lines}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(l, style: const TextStyle(color: Color(0xFFC9D2E8), fontSize: 12, height: 1.35)),
            ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Color(0xFF98A4C0), fontSize: 11, fontWeight: FontWeight.w600),
      );

  Widget _textArea(TextEditingController c, int lines) {
    return TextField(
      controller: c,
      maxLines: lines,
      style: const TextStyle(color: Color(0xFFF5F7FF), fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0E1219),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {bool digits = false, int maxLines = 1, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: maxLines,
          onChanged: onChanged,
          keyboardType: digits ? TextInputType.number : TextInputType.text,
          inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : [],
          style: const TextStyle(color: Color(0xFFF5F7FF), fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0E1219),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
        ),
      ],
    );
  }
}

/// --- Convert tenant dialog ---
class _ConvertLeadShell extends StatefulWidget {
  const _ConvertLeadShell({required this.lead, required this.onConverted});

  final Lead lead;
  final VoidCallback onConverted;

  @override
  State<_ConvertLeadShell> createState() => _ConvertLeadShellState();
}

class _ConvertLeadShellState extends State<_ConvertLeadShell> {
  late final TextEditingController _tenantId;
  late final TextEditingController _tenantEmail;
  late final TextEditingController _ownerName;
  late final TextEditingController _ownerEmail;
  late final TextEditingController _monthlyLimit;
  late final TextEditingController _monthlyPrice;
  late final TextEditingController _marginReason;
  List<CatalogPlanOption> _plans = const [];
  String? _planCode;
  String? _billingMode;
  bool _busy = false;
  String? _loadError;
  ProposalRecord? _lastProposal;
  ConvertLeadResult? _result;

  @override
  void initState() {
    super.initState();
    _tenantId = TextEditingController(text: _suggestTenantId(widget.lead.company));
    _tenantEmail = TextEditingController(text: widget.lead.email);
    _ownerName = TextEditingController(text: widget.lead.name);
    _ownerEmail = TextEditingController(text: widget.lead.email);
    _monthlyLimit = TextEditingController();
    _monthlyPrice = TextEditingController();
    _marginReason = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final lid = int.tryParse(widget.lead.id);
    try {
      final plans = (await proposalApiService.catalogPlans()).where((p) => p.isActive).toList(growable: false);
      ProposalRecord? picked;
      if (lid != null) {
        final list = await proposalApiService.list(leadId: lid);
        for (final p in list) {
          if (p.status == 'sent' && !p.isLegacy) picked = p;
        }
        picked ??= list.where((p) => !p.isLegacy).firstOrNull;
      }
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _lastProposal = picked;
        if (picked != null && plans.any((p) => p.code == picked!.planCode)) {
          _planCode = picked.planCode;
          _billingMode = picked.billingMode;
          _monthlyLimit.text = '${picked.monthlyMessageLimit}';
          _monthlyPrice.text = _moneyField(picked.monthlyValue);
        } else if (plans.isNotEmpty) {
          _applyPlan(plans.first);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = apiErrorText(e));
    }
  }

  void _applyPlan(CatalogPlanOption plan) {
    _planCode = plan.code;
    _monthlyLimit.text = plan.operationalUnits == null ? '' : '${plan.operationalUnits}';
    _monthlyPrice.text = _moneyField(plan.price);
  }

  @override
  void dispose() {
    _tenantId.dispose();
    _tenantEmail.dispose();
    _ownerName.dispose();
    _ownerEmail.dispose();
    _monthlyLimit.dispose();
    _monthlyPrice.dispose();
    _marginReason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lid = int.tryParse(widget.lead.id);
    final planCode = _planCode;
    if (lid == null || planCode == null) return;
    setState(() => _busy = true);
    try {
      final price = _parseMoney(_monthlyPrice.text);
      final result = await proposalApiService.convertLead(
        leadId: lid,
        tenantId: _tenantId.text.trim(),
        tenantEmail: _tenantEmail.text.trim(),
        ownerName: _ownerName.text.trim(),
        ownerEmail: _ownerEmail.text.trim(),
        planCode: planCode,
        billingMode: _billingMode,
        monthlyMessageLimit: _parseInt(_monthlyLimit.text),
        monthlyPrice: price > 0 ? price : null,
        marginOverrideReason: _marginReason.text,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
      widget.onConverted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _plans.where((p) => p.code == _planCode).firstOrNull;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF12161F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2E3A52)),
          ),
          child: SingleChildScrollView(
            child: _result != null
                ? _InviteResultView(
                    result: _result!,
                    fallbackWhatsapp: widget.lead.whatsapp,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cadastrar empresa',
                        style: TextStyle(color: Color(0xFFF5F7FF), fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lastProposal != null
                            ? 'Pré-preenchido com a última proposta V2 (${_lastProposal!.planCode}).'
                            : 'Pré-preenchido com o lead. Plano do catálogo V2.',
                        style: const TextStyle(color: Color(0xFF98A4C0), fontSize: 12),
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 8),
                        Text(_loadError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      _input(_tenantId, 'Tenant ID (slug)'),
                      _input(_tenantEmail, 'E-mail da empresa'),
                      _input(_ownerName, 'Nome do administrador'),
                      _input(_ownerEmail, 'E-mail do administrador'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('plan-${_plans.length}-$_planCode'),
                        initialValue: _planCode,
                        dropdownColor: const Color(0xFF1A2030),
                        style: const TextStyle(color: Color(0xFFF5F7FF)),
                        decoration: const InputDecoration(
                          labelText: 'Plano (catálogo V2)',
                          labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                        ),
                        items: _plans
                            .map((p) => DropdownMenuItem(
                                  value: p.code,
                                  child: Text(p.isCustom
                                      ? '${p.label} (sob consulta)'
                                      : '${p.label} — ${_brl(p.price ?? 0)} — ${_thousands('${p.operationalUnits ?? 0}')} msgs'),
                                ))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) {
                                final plan = _plans.where((p) => p.code == v).firstOrNull;
                                if (plan != null) setState(() => _applyPlan(plan));
                              },
                      ),
                      const SizedBox(height: 12),
                      const Text('Modo de cobrança Meta',
                          style: TextStyle(color: Color(0xFF98A4C0), fontSize: 12)),
                      const SizedBox(height: 6),
                      _BillingModeSelector(
                        value: _billingMode ?? kBillingModeCustomerDirect,
                        onChanged: _busy ? null : (m) => setState(() => _billingMode = m),
                      ),
                      if (_billingMode == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Sem seleção: usa o padrão global (cliente paga a Meta diretamente).',
                              style: TextStyle(color: Color(0xFF6E7B99), fontSize: 11)),
                        ),
                      _input(_monthlyLimit, 'Mensagens operacionais entregues / mês', number: true),
                      _input(_monthlyPrice, 'Mensalidade (R\$)'),
                      _input(_marginReason, 'Justificativa de margem (obrigatória se abaixo de 30% ou com desconto)'),
                      if (selected?.isCustom == true)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Plano sob consulta: franquia e mensalidade são obrigatórias.',
                              style: TextStyle(color: AppColors.warning, fontSize: 11)),
                        ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => Navigator.of(context).pop(),
                            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF98A4C0))),
                          ),
                          const Spacer(),
                          PremiumAccentButton(
                            label: _busy ? 'Criando...' : 'Criar empresa e gerar convite',
                            icon: Icons.apartment_rounded,
                            onPressed: (_busy || _planCode == null) ? null : _submit,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String label, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: Color(0xFFF5F7FF)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF98A4C0)),
      ),
    );
  }
}

String? _whatsAppDigits(String? raw) {
  var digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 10 || digits.length == 11) digits = '55$digits';
  return digits.length >= 12 ? digits : null;
}

class _InviteResultView extends StatelessWidget {
  const _InviteResultView({required this.result, required this.fallbackWhatsapp});

  final ConvertLeadResult result;
  final String fallbackWhatsapp;

  static const _text = Color(0xFFF5F7FF);
  static const _muted = Color(0xFF98A4C0);

  String get _ownerFirstName {
    final name = (result.ownerName ?? '').trim();
    return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
  }

  String _message(String url) {
    final greeting = _ownerFirstName.isEmpty ? 'Olá!' : 'Olá, $_ownerFirstName!';
    return '$greeting Seu acesso ao painel Atende Ai de ${result.tenantName} foi criado. '
        'Defina sua senha por este link: $url';
  }

  ({IconData icon, Color color, String title, String body}) _emailState() {
    final email = result.ownerEmail ?? '';
    switch (result.emailStatus) {
      case 'sent':
        return (
          icon: Icons.mark_email_read_rounded,
          color: AppColors.success,
          title: 'E-mail enviado',
          body: 'Convite enviado para $email.',
        );
      case 'failed':
        return (
          icon: Icons.error_outline_rounded,
          color: AppColors.danger,
          title: 'Falha ao enviar e-mail',
          body: 'O servidor de e-mail recusou o envio. Envie o link abaixo manualmente.',
        );
      case 'skipped':
        return (
          icon: Icons.info_outline_rounded,
          color: AppColors.warning,
          title: 'E-mail não enviado',
          body: 'O envio de e-mail ainda não está configurado. Envie o link abaixo pelo WhatsApp ou copie e compartilhe.',
        );
      default:
        return (
          icon: Icons.info_outline_rounded,
          color: AppColors.warning,
          title: 'Convite não gerado',
          body: 'A empresa foi criada, mas o convite não pôde ser gerado. Gere um novo em Equipe.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = result.inviteUrl;
    final state = _emailState();
    final phone = _whatsAppDigits(result.ownerWhatsapp ?? fallbackWhatsapp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Empresa ${result.tenantName} criada',
                style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: state.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: state.color.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(state.icon, color: state.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(state.body, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (url != null) ...[
          const SizedBox(height: 16),
          const Text('Link de acesso', style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E3A52)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    maxLines: 2,
                    style: const TextStyle(color: _text, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar link',
                  icon: const Icon(Icons.copy_rounded, size: 18, color: _muted),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copiado.')),
                    );
                  },
                ),
              ],
            ),
          ),
          if (result.inviteExpiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Válido até ${_formatDate(result.inviteExpiresAt!.toLocal())}.',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Concluir', style: TextStyle(color: _muted)),
            ),
            if (url != null && phone != null)
              PremiumAccentButton(
                label: 'Enviar pelo WhatsApp',
                icon: Icons.chat_rounded,
                onPressed: () => launchUrl(
                  Uri.https('wa.me', '/$phone', {'text': _message(url)}),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} às ${two(d.hour)}:${two(d.minute)}';
  }
}
