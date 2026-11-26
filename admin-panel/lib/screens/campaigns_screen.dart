import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/campaign.dart';
import '../models/whatsapp_account.dart';
import '../models/whatsapp_template.dart';
import '../services/auth_service.dart';
import '../services/campaign_service.dart';
import '../services/whatsapp_account_service.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_tokens.dart';
import '../utils/web_download_stub.dart'
    if (dart.library.html) '../utils/web_download_web.dart' as web_dl;

/// Campanhas em massa: criar, validar XLSX e acompanhar progresso.
const _kMetaDisclaimer =
    'As mensagens são cobradas diretamente pela Meta na forma de pagamento vinculada '
    'à sua conta WhatsApp Business. Os valores apresentados pelo Atende Ai são estimativas.';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  bool _loading = true;
  String? _error;
  List<CampaignSummaryModel> _items = [];
  List<WhatsAppAccountModel> _accounts = [];
  List<WhatsAppTemplateModel> _templates = [];
  CampaignSummaryModel? _selected;
  CampaignValidationModel? _validation;

  String get _tenantId => authService.tenantId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_tenantId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await whatsAppAccountService.listAccounts(_tenantId);
      final templates = await whatsAppTemplateService.listTemplates(_tenantId);
      final campaigns = await campaignService.listCampaigns(_tenantId);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _templates = templates.where((t) => t.status.toUpperCase() == 'APPROVED').toList();
        _items = campaigns;
      });
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCampaign() async {
    final nameCtrl = TextEditingController();
    var nameDraft = '';
    String? accountKey = _accounts.isNotEmpty ? _accounts.first.accountKey : null;
    WhatsAppTemplateModel? tpl = _templates.isNotEmpty ? _templates.first : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Nova campanha'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome da campanha'),
                onChanged: (v) => setLocal(() => nameDraft = v),
                onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: accountKey,
                items: _accounts
                    .map((a) => DropdownMenuItem(value: a.accountKey, child: Text(a.displayPhoneNumber)))
                    .toList(),
                onChanged: (v) => setLocal(() => accountKey = v),
                decoration: const InputDecoration(labelText: 'Conta WhatsApp'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<WhatsAppTemplateModel>(
                value: tpl,
                items: _templates
                    .map((t) => DropdownMenuItem(value: t, child: Text('${t.name} (${t.language})')))
                    .toList(),
                onChanged: (v) => setLocal(() => tpl = v),
                decoration: const InputDecoration(labelText: 'Template aprovado'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(ctx, true);
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    final chosen = tpl;
  final resolvedName =
        nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : nameDraft.trim();
    if (ok != true || chosen == null || resolvedName.isEmpty) return;
    try {
      final created = await campaignService.createCampaign(
        tenantId: _tenantId,
        name: resolvedName,
        templateName: chosen.name,
        templateLanguage: chosen.language,
        accountKey: accountKey,
      );
      await _load();
      setState(() => _selected = created);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  void _saveBytesAsFile(Uint8List bytes, String filename) {
    web_dl.webDownloadBytes(bytes, filename);
  }

  Future<void> _downloadTemplate(CampaignSummaryModel item) async {
    try {
      final bytes = await campaignService.downloadImportTemplate(
        tenantId: _tenantId,
        campaignId: item.id,
      );
      _saveBytesAsFile(bytes, 'campanha-${item.id}.xlsx');
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _uploadXlsx(CampaignSummaryModel item) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    try {
      final validation = await campaignService.validateUpload(
        tenantId: _tenantId,
        campaignId: item.id,
        bytes: file.bytes!,
        filename: file.name,
      );
      setState(() {
        _selected = item;
        _validation = validation;
      });
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _downloadResults(CampaignSummaryModel item) async {
    try {
      final bytes = await campaignService.downloadResults(
        tenantId: _tenantId,
        campaignId: item.id,
      );
      _saveBytesAsFile(bytes, 'resultados-${item.id}.xlsx');
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _start(CampaignSummaryModel item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar disparo'),
        content: Text(
          'Enviar para ${item.totalRecipients} destinatário(s)?\n\n'
          'Previsão (entregues): ${item.metaEstimate['total_if_all_delivered_estimate'] ?? '—'} '
          '${item.metaEstimate['currency'] ?? 'BRL'} · categoria ${item.templateCategory}.\n\n'
          '$_kMetaDisclaimer',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await campaignService.startCampaign(tenantId: _tenantId, campaignId: item.id);
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Campanhas em massa',
                  style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: _templates.isEmpty ? null : _createCampaign,
                icon: const Icon(Icons.add),
                label: const Text('Nova campanha'),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(_kMetaDisclaimer, style: TextStyle(color: AppColors.textSoft, fontSize: 11)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              return Card(
                color: AppColors.surface,
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.templateName} · ${item.status}\n'
                    'pend: ${item.pendingCount} env: ${item.sentCount} ent: ${item.deliveredCount} '
                    'lid: ${item.readCount} falha: ${item.failedCount} incerto: ${item.uncertainCount}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Baixar modelo XLSX',
                        onPressed: () => _downloadTemplate(item),
                        icon: const Icon(Icons.download),
                      ),
                      IconButton(
                        tooltip: 'Importar destinatários',
                        onPressed: () => _uploadXlsx(item),
                        icon: const Icon(Icons.upload_file),
                      ),
                      if (item.status == 'validated' || item.status == 'paused')
                        IconButton(
                          tooltip: 'Iniciar',
                          onPressed: () => _start(item),
                          icon: const Icon(Icons.play_arrow),
                        ),
                      IconButton(
                        tooltip: 'Exportar resultados',
                        onPressed: () => _downloadResults(item),
                        icon: const Icon(Icons.table_view),
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _selected = item),
                ),
              );
            },
          ),
        ),
        if (_validation != null && _selected != null)
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceAlt,
            child: Text(
              'Validação: ${_validation!.validRows}/${_validation!.totalRows} linhas OK'
              '${_validation!.sendsEnabled ? '' : ' — envios bloqueados: ${_validation!.sendsBlockedReason ?? ''}'}\n'
              'Previsão: ${_validation!.estimate['total_if_all_delivered_estimate'] ?? '—'} '
              '${_validation!.estimate['currency'] ?? 'BRL'}\n'
              '${_validation!.metaDisclaimer ?? _kMetaDisclaimer}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}