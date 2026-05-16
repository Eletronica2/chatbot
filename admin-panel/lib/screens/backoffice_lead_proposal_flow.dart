import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../services/api_client.dart';
import '../services/lead_service.dart';
import '../services/pdf/proposal_pdf.dart';
import '../services/proposal_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

const _kPlanKeys = [
  'starter',
  'growth_basic',
  'growth',
  'pro',
  'enterprise',
];

String _planLabelPt(String key) {
  switch (key) {
    case 'starter':
      return 'Inicial';
    case 'growth_basic':
      return 'Crescimento Básico';
    case 'growth':
      return 'Crescimento';
    case 'pro':
      return 'Profissional';
    case 'enterprise':
      return 'Empresarial';
    default:
      return key;
  }
}

String _suggestTenantId(String companyName) {
  final raw = companyName
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  if (raw.isEmpty) return 'empresa_nova';
  return raw.replaceAll(RegExp(r'_+'), '_');
}

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

/// --- Proposal dialog ---
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
  String? _error;

  String _selectedPlan = 'starter';

  late final TextEditingController _monthly;
  late final TextEditingController _setup;
  late final TextEditingController _limit;
  late final TextEditingController _validity;
  late final TextEditingController _items;
  late final TextEditingController _notes;

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final rid = int.tryParse(widget.lead.id);
      if (rid == null) {
        setState(() {
          _loading = false;
          _error = 'ID de lead invalido.';
        });
        return;
      }
      final rec = await proposalApiService.recommendationForLead(rid);
      if (!mounted) return;
      setState(() {
        _rec = rec;
        _selectedPlan = rec.plan;
        _monthly.text = rec.monthlyValue.toStringAsFixed(2).replaceAll('.', ',');
        _setup.text = rec.setupFee.toStringAsFixed(2).replaceAll('.', ',');
        _limit.text = '${rec.monthlyMessageLimit}';
        _items.text = rec.includedItems.join('\n');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar recomendação: $e';
      });
    }
  }

  @override
  void dispose() {
    _monthly.dispose();
    _setup.dispose();
    _limit.dispose();
    _validity.dispose();
    _items.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _parseMoney(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^\d,.-]'), '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  int _parseInt(String raw) => int.tryParse(raw.trim().replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  List<String> _parseItems(String raw) {
    return raw
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  void _applyPlanDefaults(String plan) {
    final rec = _rec;
    if (rec != null && plan == rec.plan) {
      setState(() {
        _selectedPlan = plan;
        _monthly.text = rec.monthlyValue.toStringAsFixed(2).replaceAll('.', ',');
        _setup.text = rec.setupFee.toStringAsFixed(2).replaceAll('.', ',');
        _limit.text = '${rec.monthlyMessageLimit}';
        _items.text = rec.includedItems.join('\n');
      });
      return;
    }
    _fallbackPlanDefaults(plan);
  }

  void _fallbackPlanDefaults(String plan) {
    final defaults = {
      'starter': (197.0, 497.0, 500),
      'growth_basic': (397.0, 897.0, 2000),
      'growth': (697.0, 1497.0, 5000),
      'pro': (1197.0, 2497.0, 20000),
      'enterprise': (2497.0, 4997.0, 100000),
    };
    final d = defaults[plan] ?? defaults['starter']!;
    setState(() {
      _selectedPlan = plan;
      _monthly.text = d.$1.toStringAsFixed(2).replaceAll('.', ',');
      _setup.text = d.$2.toStringAsFixed(2).replaceAll('.', ',');
      _limit.text = '${d.$3}';
      _items.text = _presetItems(plan);
    });
  }

  String _presetItems(String plan) {
    switch (plan) {
      case 'starter':
        return 'Automação base sob medida\nAtendimento humano integrado\n1 número de WhatsApp Cloud API\nSuporte por e-mail';
      case 'growth_basic':
        return 'Automação base + 1 ação personalizada\nTreinamento da equipe (1h)\n1 número de WhatsApp Cloud API';
      case 'growth':
        return 'Automação base + 3 ações personalizadas\nTreinamento (2h)\nIntegrações HTTP';
      case 'pro':
        return 'Automação base + ações ilimitadas\nTreinamento (4h)\nDashboards operacionais';
      case 'enterprise':
        return 'Implantação consultiva dedicada\nMulti-número e integrações complexas';
      default:
        return '';
    }
  }

  Future<void> _saveSent() async {
    final rid = int.tryParse(widget.lead.id);
    if (rid == null) return;
    setState(() => _savingSent = true);
    try {
      await proposalApiService.create(
        leadId: rid,
        companyName: widget.lead.company,
        contactName: widget.lead.name,
        contactEmail: widget.lead.email,
        contactWhatsapp: widget.lead.whatsapp,
        plan: _selectedPlan,
        monthlyValue: _parseMoney(_monthly.text),
        setupFee: _parseMoney(_setup.text),
        monthlyMessageLimit: _parseInt(_limit.text),
        includedItems:
            _parseItems(_items.text).isNotEmpty ? _parseItems(_items.text) : _presetItems(_selectedPlan).split('\n'),
        validityDays: _parseInt(_validity.text).clamp(1, 180),
        status: 'sent',
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      final msg = e is ApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF151925), Color(0xFF0B0E14)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                              style: TextStyle(
                                color: Color(0xFFF5F7FF),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
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
                        style: const TextStyle(
                          color: Color(0xFFF5F7FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.lead.name} • ${widget.lead.email}',
                        style: const TextStyle(color: Color(0xFF98A4C0), fontSize: 12),
                      ),
                      if (_rec != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Recomendação: ${_planLabelPt(_rec!.plan)} • ${_rec!.rationale}',
                          style: const TextStyle(color: Color(0xFF6E7B99), fontSize: 11, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Plano',
                        style: TextStyle(color: Color(0xFF98A4C0), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final k in _kPlanKeys)
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_planLabelPt(k)),
                                  if (_rec?.plan == k) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'Sugerido',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              selected: _selectedPlan == k,
                              onSelected: (_) => _applyPlanDefaults(k),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _field('Mensalidade (R\$)', _monthly),
                      const SizedBox(height: 10),
                      _field('Implantação / treino (R\$)', _setup),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _field('Limite mensagens / mês', _limit)),
                          const SizedBox(width: 12),
                          Expanded(child: _field('Validade (dias)', _validity)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Itens incluídos (1 por linha)',
                        style: TextStyle(color: Color(0xFF98A4C0), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _items,
                        maxLines: 5,
                        style: const TextStyle(color: Color(0xFFF5F7FF), fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0E1219),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Observações internas',
                        style: TextStyle(color: Color(0xFF98A4C0), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _notes,
                        maxLines: 2,
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
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: PremiumAccentButton(
                              label: _savingSent ? 'Salvando...' : 'Salvar como enviada',
                              icon: Icons.send_rounded,
                              dense: true,
                              expand: true,
                              onPressed: _savingSent ? null : _saveSent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PremiumAccentButton(
                              label: 'Baixar PDF',
                              icon: Icons.picture_as_pdf_rounded,
                              dense: true,
                              expand: true,
                              onPressed: () {
                                Printing.layoutPdf(
                                  name: 'proposta_${widget.lead.company}.pdf',
                                  onLayout: (_) async =>
                                      buildProposalPdf(
                                        ProposalPdfData(
                                          companyName: widget.lead.company,
                                          contactName: widget.lead.name,
                                          contactEmail: widget.lead.email,
                                          contactWhatsapp: widget.lead.whatsapp,
                                          planLabel: _planLabelPt(_selectedPlan),
                                          planKey: _selectedPlan,
                                          monthlyValue: _parseMoney(_monthly.text),
                                          setupFee: _parseMoney(_setup.text),
                                          monthlyMessageLimit: _parseInt(_limit.text),
                                          includedItems: _parseItems(_items.text).isNotEmpty
                                              ? _parseItems(_items.text)
                                              : _presetItems(_selectedPlan).split('\n'),
                                          validityDays:
                                              _parseInt(_validity.text).clamp(1, 180),
                                          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                                        ),
                                      ),
                                );
                              },
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

  Widget _field(String label, TextEditingController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF98A4C0), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: TextInputType.text,
          inputFormatters: label.contains('dia') ? [FilteringTextInputFormatter.digitsOnly] : [],
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
  String _plan = 'starter';
  bool _busy = false;
  ProposalRecord? _lastProposal;

  @override
  void initState() {
    super.initState();
    _tenantId = TextEditingController(text: _suggestTenantId(widget.lead.company));
    _tenantEmail = TextEditingController(text: widget.lead.email);
    _ownerName = TextEditingController(text: widget.lead.name);
    _ownerEmail = TextEditingController(text: widget.lead.email);
    _monthlyLimit = TextEditingController(text: '1000');
    _loadProposal();
  }

  Future<void> _loadProposal() async {
    final lid = int.tryParse(widget.lead.id);
    if (lid == null) return;
    try {
      final list = await proposalApiService.list(leadId: lid);
      ProposalRecord? picked;
      for (final p in list) {
        if (p.status == 'sent') picked = p;
      }
      picked ??= list.isNotEmpty ? list.first : null;
      if (!mounted || picked == null) return;
      setState(() {
        _lastProposal = picked!;
        _plan = picked.plan;
        _monthlyLimit.text = '${picked.monthlyMessageLimit}';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tenantId.dispose();
    _tenantEmail.dispose();
    _ownerName.dispose();
    _ownerEmail.dispose();
    _monthlyLimit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lid = int.tryParse(widget.lead.id);
    if (lid == null) return;
    setState(() => _busy = true);
    try {
      await proposalApiService.convertLead(
        leadId: lid,
        tenantId: _tenantId.text.trim(),
        tenantEmail: _tenantEmail.text.trim(),
        ownerName: _ownerName.text.trim(),
        ownerEmail: _ownerEmail.text.trim(),
        plan: _plan,
        monthlyMessageLimit: int.tryParse(_monthlyLimit.text.trim()) ?? 1000,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Empresa criada (${_tenantId.text.trim()}). Convite para ${_ownerEmail.text.trim()}.',
          ),
        ),
      );
      widget.onConverted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      String msg = e.toString();
      if (e is ApiException) {
        msg = e.message.length > 200 ? e.message.substring(0, 200) : e.message;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF12161F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2E3A52)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cadastrar empresa',
                  style: TextStyle(color: Color(0xFFF5F7FF), fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pré-preenche com o lead ${_lastProposal != null ? "(última proposta encontrada)." : "."}',
                  style: const TextStyle(color: Color(0xFF98A4C0), fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tenantId,
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'Tenant ID (slug)',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
                ),
                TextField(
                  controller: _tenantEmail,
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'E-mail da empresa',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
                ),
                TextField(
                  controller: _ownerName,
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'Nome do administrador',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
                ),
                TextField(
                  controller: _ownerEmail,
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'E-mail do administrador',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _plan,
                  dropdownColor: const Color(0xFF1A2030),
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'Plano',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
                  items: _kPlanKeys
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(_planLabelPt(k)),
                        ),
                      )
                      .toList(),
                  onChanged: _busy ? null : (v) => setState(() => _plan = v ?? _plan),
                ),
                TextField(
                  controller: _monthlyLimit,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Color(0xFFF5F7FF)),
                  decoration: const InputDecoration(
                    labelText: 'Limite mensal de mensagens',
                    labelStyle: TextStyle(color: Color(0xFF98A4C0)),
                  ),
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
                      label: _busy ? 'Criando...' : 'Criar empresa e enviar convite',
                      icon: Icons.apartment_rounded,
                      onPressed: _busy ? null : _submit,
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
}
