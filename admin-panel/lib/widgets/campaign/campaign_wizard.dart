import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/campaign.dart';
import '../../models/whatsapp_account.dart';
import '../../models/whatsapp_template.dart';
import '../../services/campaign_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/campaign_format.dart';
import '../../utils/template_preview_mapper.dart';
import '../../utils/web_download_stub.dart'
    if (dart.library.html) '../../utils/web_download_web.dart' as web_dl;
import '../whatsapp_template_phone_preview.dart';
import 'campaign_ui.dart';

class CampaignWizardFlow extends StatefulWidget {
  const CampaignWizardFlow({
    super.key,
    required this.tenantId,
    required this.accounts,
    required this.templates,
    required this.sendReadiness,
    this.existing,
    this.initialStep = 0,
    this.onFinished,
    this.onOpenBilling,
  });

  final String tenantId;
  final List<WhatsAppAccountModel> accounts;
  final List<WhatsAppTemplateModel> templates;
  final CampaignSendReadinessModel sendReadiness;
  final CampaignSummaryModel? existing;
  final int initialStep;
  final VoidCallback? onFinished;
  final VoidCallback? onOpenBilling;

  static Future<void> show(
    BuildContext context, {
    required CampaignWizardFlow widget,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.backgroundElevated,
        insetPadding: EdgeInsets.symmetric(
          horizontal: AppBreakpoints.isCompact(ctx) ? 12 : 32,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
          child: widget,
        ),
      ),
    );
  }

  @override
  State<CampaignWizardFlow> createState() => _CampaignWizardFlowState();
}

class _CampaignWizardFlowState extends State<CampaignWizardFlow> {
  late int _step;
  final _nameCtrl = TextEditingController();
  var _nameDraft = '';
  String? _accountKey;
  WhatsAppTemplateModel? _template;
  CampaignSummaryModel? _campaign;
  CampaignValidationModel? _validation;
  String? _pickedFileName;
  bool _busy = false;
  bool _recipientAuthorization = false;
  String? _error;

  static const _titles = ['Informações', 'Destinatários', 'Revisão', 'Confirmação'];

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _campaign = widget.existing;
    if (_campaign != null && _step == 0) {
      _step = 1;
      _nameCtrl.text = _campaign!.name;
    }
    _accountKey = _campaign?.accountKey ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.accountKey : null);
    if (_campaign != null) {
      _template = widget.templates
              .where((t) => t.name == _campaign!.templateName)
              .firstOrNull ??
          (widget.templates.isNotEmpty ? widget.templates.first : null);
    } else {
      _template = widget.templates.isNotEmpty ? widget.templates.first : null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    final name =
        _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : _nameDraft.trim();
    final tpl = _template;
    if (name.isEmpty || tpl == null) {
      setState(() => _error = 'Preencha o nome e selecione um template.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final created = await campaignService.createCampaign(
        tenantId: widget.tenantId,
        name: name,
        templateName: tpl.name,
        templateLanguage: tpl.language,
        accountKey: _accountKey,
      );
      if (!mounted) return;
      setState(() {
        _campaign = created;
        _step = 1;
      });
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickXlsx() async {
    final campaign = _campaign;
    if (campaign == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _pickedFileName = file.name;
    });
    try {
      final validation = await campaignService.validateUpload(
        tenantId: widget.tenantId,
        campaignId: campaign.id,
        bytes: file.bytes!,
        filename: file.name,
      );
      if (!mounted) return;
      final detail = await campaignService.getCampaignDetail(
        tenantId: widget.tenantId,
        campaignId: campaign.id,
      );
      if (!mounted) return;
      setState(() {
        _validation = validation;
        _campaign = detail.campaign;
      });
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadModel() async {
    final campaign = _campaign;
    if (campaign == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await campaignService.downloadImportTemplate(
        tenantId: widget.tenantId,
        campaignId: campaign.id,
      );
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final messenger = ScaffoldMessenger.of(context);
      // download handled by caller pattern - import web download
      _saveBytes(bytes, 'campanha-${campaign.id}.xlsx');
      messenger.showSnackBar(const SnackBar(content: Text('Modelo XLSX baixado.')));
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveBytes(Uint8List bytes, String name) {
    web_dl.webDownloadBytes(bytes, name);
  }

  bool get _canStart {
    final v = _validation;
    if (v == null || v.validRows < 1) return false;
    if (!v.sendsEnabled) return false;
    if (!widget.sendReadiness.sendsEnabled) return false;
    if (!_recipientAuthorization) return false;
    return _campaign?.status == 'validated' || _campaign?.status == 'paused';
  }

  Future<void> _confirmStart() async {
    final campaign = _campaign;
    if (campaign == null || !_canStart) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await campaignService.startCampaign(
        tenantId: widget.tenantId,
        campaignId: campaign.id,
        confirm: true,
        recipientAuthorization: true,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onFinished?.call();
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppBreakpoints.isCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nova campanha',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Etapa ${_step + 1} de 4 · ${_titles[_step]}',
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _StepperDots(current: _step, total: 4),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _buildStep(compact),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _step -= 1),
                  child: const Text('Voltar'),
                ),
              const Spacer(),
              if (_step == 0)
                FilledButton(
                  onPressed: _busy ? null : _createDraft,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Continuar'),
                )
              else if (_step < 3)
                FilledButton(
                  onPressed: _busy ? null : _nextStep,
                  child: const Text('Continuar'),
                )
              else
                FilledButton(
                  onPressed: (_busy || !_canStart) ? null : _confirmStart,
                  child: const Text('Confirmar e iniciar'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _nextStep() {
    if (_step == 1 && (_validation == null || _validation!.validRows < 1)) {
      setState(() => _error = 'Importe e valide ao menos um destinatário.');
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  Widget _buildStep(bool compact) {
    switch (_step) {
      case 0:
        return _stepInfo();
      case 1:
        return _stepRecipients(compact);
      case 2:
        return _stepReview(compact);
      default:
        return _stepConfirm(compact);
    }
  }

  Widget _stepInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da campanha'),
          onChanged: (v) => setState(() => _nameDraft = v),
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: _accountKey,
          decoration: const InputDecoration(labelText: 'Conta WhatsApp'),
          items: widget.accounts
              .map((a) => DropdownMenuItem(value: a.accountKey, child: Text(a.displayPhoneNumber)))
              .toList(),
          onChanged: (v) => setState(() => _accountKey = v),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<WhatsAppTemplateModel>(
          value: _template,
          decoration: const InputDecoration(labelText: 'Template aprovado'),
          items: widget.templates
              .map((t) => DropdownMenuItem(value: t, child: Text('${t.name} (${t.language})')))
              .toList(),
          onChanged: (v) => setState(() => _template = v),
        ),
        if (_template != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Categoria: ${_template!.category}',
            style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _stepRecipients(bool compact) {
    final v = _validation;
    final sendOk = widget.sendReadiness.sendsEnabled && (v?.sendsEnabled ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.sendReadiness.sendsEnabled)
          CampaignSendBlockBanner(
            title: 'Envio bloqueado pelo plano',
            message: widget.sendReadiness.sendsBlockedReason ?? 'Plano indisponível.',
            onOpenPlan: widget.onOpenBilling,
          ),
        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: _busy ? null : _pickXlsx,
          borderRadius: AppRadius.lg,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.border, width: 1.2),
              color: AppColors.surface,
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file, size: 36, color: AppColors.primary.withValues(alpha: 0.85)),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Arraste ou clique para importar',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Arquivo .xlsx · aba Destinatários',
                  style: TextStyle(color: AppColors.textSoft, fontSize: 12),
                ),
                if (_pickedFileName != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_pickedFileName!, style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _downloadModel,
              icon: const Icon(Icons.download),
              label: const Text('Baixar modelo XLSX'),
            ),
            if (_pickedFileName != null)
              TextButton(onPressed: _busy ? null : _pickXlsx, child: const Text('Trocar arquivo')),
          ],
        ),
        if (v != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ValidationStats(validation: v),
          if (!sendOk) ...[
            const SizedBox(height: AppSpacing.md),
            CampaignSendBlockBanner(
              title: 'Planilha válida, envio não autorizado',
              message: v.sendsBlockedReason ?? widget.sendReadiness.sendsBlockedReason ?? '',
              onOpenPlan: widget.onOpenBilling,
            ),
          ],
          if (v.recipients.any((r) => r.errors.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.md),
            ...v.recipients.where((r) => r.errors.isNotEmpty).map(
                  (r) => Text(
                    'Linha ${r.rowNumber}: ${r.errors.join('; ')}',
                    style: const TextStyle(color: AppColors.danger, fontSize: 11),
                  ),
                ),
          ],
        ],
      ],
    );
  }

  Widget _stepReview(bool compact) {
    final tpl = _template;
    final v = _validation;
    final previewRecipient =
        v == null ? null : v.recipients.where((r) => r.errors.isEmpty).firstOrNull;
    final paramValues = <String>[];
    if (previewRecipient != null && tpl != null) {
      final keys = <String>[];
      final body = tpl.bodyText;
      if (body != null) {
        keys.addAll(
          RegExp(r'\{\{(\d+)\}\}')
              .allMatches(body)
              .map((m) => m.group(1)!)
              .toSet(),
        );
        keys.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      }
      for (final k in keys) {
        paramValues.add(previewRecipient.bodyParams[k] ?? '');
      }
    }
    final business = widget.accounts
            .where((a) => a.accountKey == _accountKey)
            .map((a) => a.displayPhoneNumber)
            .firstOrNull ??
        'WhatsApp';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tpl != null && compact)
          WhatsAppTemplatePhonePreviewFrame(
            data: TemplatePreviewMapper.fromTemplate(
              template: tpl,
              businessName: business,
              bodyParameterValues: paramValues,
            ),
          ),
        if (tpl != null && !compact)
          Center(
            child: SizedBox(
              width: 320,
              child: WhatsAppTemplatePhonePreviewFrame(
                data: TemplatePreviewMapper.fromTemplate(
                  template: tpl,
                  businessName: business,
                  bodyParameterValues: paramValues,
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        _reviewRow('Template', tpl?.name ?? '—'),
        _reviewRow('Destinatários válidos', '${v?.validRows ?? 0}'),
        _reviewRow('Estimativa Meta', formatCampaignMetaEstimate(v?.estimate)),
        const SizedBox(height: AppSpacing.sm),
        Text(kCampaignMetaDisclaimer, style: const TextStyle(color: AppColors.textSoft, fontSize: 11)),
        if (v != null && !v.sendsEnabled) ...[
          const SizedBox(height: AppSpacing.md),
          CampaignSendBlockBanner(
            title: 'Disparo indisponível',
            message: v.sendsBlockedReason ?? '',
            onOpenPlan: widget.onOpenBilling,
          ),
        ],
      ],
    );
  }

  Widget _stepConfirm(bool compact) {
    final c = _campaign;
    final v = _validation;
    final account = widget.accounts.where((a) => a.accountKey == c?.accountKey).firstOrNull;
    final blocked = !_canStart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirme o disparo',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
        ),
        const SizedBox(height: AppSpacing.md),
        _reviewRow('Campanha', c?.name ?? '—'),
        _reviewRow('Template', c?.templateName ?? '—'),
        _reviewRow('Conta', account?.displayPhoneNumber ?? '—'),
        _reviewRow('Destinatários', '${v?.validRows ?? 0}'),
        _reviewRow('Custo Meta (est.)', formatCampaignMetaEstimate(v?.estimate)),
        if (v?.planSnapshot != null)
          _reviewRow(
            'Plano Atende Ai',
            '${v!.planSnapshot!.plan} · ${v.planSnapshot!.status}',
          ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: _recipientAuthorization,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Declaro que estou autorizado a contatar estes destinatários. Esta confirmação não registra o consentimento de cada pessoa.',
            style: TextStyle(color: AppColors.text, fontSize: 13),
          ),
          onChanged: (value) => setState(() => _recipientAuthorization = value ?? false),
        ),
        Text(kCampaignMetaDisclaimer, style: const TextStyle(color: AppColors.textSoft, fontSize: 11)),
        if (blocked) ...[
          const SizedBox(height: AppSpacing.md),
          CampaignSendBlockBanner(
            title: 'Não é possível iniciar',
            message: v?.sendsBlockedReason ??
                widget.sendReadiness.sendsBlockedReason ??
                'Verifique o plano e a validação.',
            onOpenPlan: widget.onOpenBilling,
          ),
        ],
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StepperDots extends StatelessWidget {
  const _StepperDots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: AppRadius.pill,
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
        );
      }),
    );
  }
}

class _ValidationStats extends StatelessWidget {
  const _ValidationStats({required this.validation});
  final CampaignValidationModel validation;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _chip('Total', validation.totalRows, AppColors.text),
        _chip('Válidas', validation.validRows, AppColors.success),
        _chip('Inválidas', validation.invalidRows, AppColors.danger),
        _chip('Duplicadas', validation.duplicatePhones, AppColors.warning),
        _chip('Não autorizados', validation.consentMissingRows, AppColors.warning),
      ],
    );
  }

  Widget _chip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Text('$label: $value', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}