import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/campaign.dart';
import '../models/whatsapp_account.dart';
import '../models/whatsapp_template.dart';
import '../services/auth_service.dart';
import '../services/campaign_service.dart';
import '../services/whatsapp_account_service.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_tokens.dart';
import '../utils/campaign_format.dart';
import '../utils/web_download_stub.dart'
    if (dart.library.html) '../utils/web_download_web.dart' as web_dl;
import '../widgets/campaign/campaign_detail_panel.dart';
import '../widgets/campaign/campaign_ui.dart';
import '../widgets/campaign/campaign_wizard.dart';
import '../widgets/ui_kit.dart';

/// Campanhas WhatsApp — listagem premium, wizard e detalhes.
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key, this.onOpenBilling});

  final VoidCallback? onOpenBilling;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  bool _loading = true;
  String? _error;
  List<CampaignSummaryModel> _items = [];
  List<WhatsAppAccountModel> _accounts = [];
  List<WhatsAppTemplateModel> _templates = [];
  CampaignSendReadinessModel? _sendReadiness;

  String? _selectedId;
  CampaignDetailModel? _detail;
  bool _detailLoading = false;

  String _search = '';
  String? _statusFilter;
  _CampaignSort _sort = _CampaignSort.recent;

  String get _tenantId => authService.tenantId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool keepSelection = true}) async {
    if (_tenantId.isEmpty) return;
    final prev = _selectedId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        whatsAppAccountService.listAccounts(_tenantId),
        whatsAppTemplateService.listTemplates(_tenantId),
        campaignService.listCampaigns(_tenantId),
        campaignService.getSendReadiness(_tenantId),
      ]);
      if (!mounted) return;
      final accounts = results[0] as List<WhatsAppAccountModel>;
      final templates = results[1] as List<WhatsAppTemplateModel>;
      final campaigns = results[2] as List<CampaignSummaryModel>;
      final readiness = results[3] as CampaignSendReadinessModel;
      setState(() {
        _accounts = accounts;
        _templates = templates.where((t) => t.status.toUpperCase() == 'APPROVED').toList();
        _items = campaigns;
        _sendReadiness = readiness;
      });
      if (keepSelection && prev != null && campaigns.any((c) => c.id == prev)) {
        await _openDetail(prev);
      }
    } catch (err) {
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(String id) async {
    setState(() {
      _selectedId = id;
      _detailLoading = true;
    });
    try {
      final detail = await campaignService.getCampaignDetail(tenantId: _tenantId, campaignId: id);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  List<CampaignSummaryModel> get _visibleItems {
    var items = List<CampaignSummaryModel>.from(_items);
    if (_statusFilter != null) {
      items = items.where((c) => c.status == _statusFilter).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      items = items.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case _CampaignSort.recent:
        items.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      case _CampaignSort.name:
        items.sort((a, b) => a.name.compareTo(b.name));
      case _CampaignSort.status:
        items.sort((a, b) => a.status.compareTo(b.status));
    }
    return items;
  }

  ({int? sent, int? delivered, double? rate, String? metaSum}) _aggregateMetrics() {
    if (_items.isEmpty) return (sent: null, delivered: null, rate: null, metaSum: null);
    var sent = 0;
    var delivered = 0;
    var failed = 0;
    var uncertain = 0;
    double metaSum = 0;
    var hasMeta = false;
    for (final c in _items) {
      sent += c.sentCount + c.deliveredCount + c.readCount + c.failedCount + c.uncertainCount;
      delivered += c.deliveredCount + c.readCount;
      failed += c.failedCount;
      uncertain += c.uncertainCount;
      final raw = c.metaEstimate['total_if_all_delivered_estimate'];
      final val = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (val != null && val > 0) {
        metaSum += val;
        hasMeta = true;
      }
    }
    final denom = delivered + failed + uncertain;
    final rate = denom > 0 ? delivered / denom : null;
    return (
      sent: sent > 0 ? sent : null,
      delivered: delivered > 0 ? delivered : null,
      rate: rate,
      metaSum: hasMeta ? formatCampaignMoney(metaSum) : null,
    );
  }

  void _saveBytes(Uint8List bytes, String name) => web_dl.webDownloadBytes(bytes, name);

  Future<void> _openWizard({CampaignSummaryModel? existing, int initialStep = 0}) async {
    final readiness = _sendReadiness;
    if (readiness == null) return;
    await CampaignWizardFlow.show(
      context,
      widget: CampaignWizardFlow(
        tenantId: _tenantId,
        accounts: _accounts,
        templates: _templates,
        sendReadiness: readiness,
        existing: existing,
        initialStep: initialStep,
        onOpenBilling: widget.onOpenBilling,
        onFinished: () => _load(),
      ),
    );
  }

  Future<void> _importFor(CampaignSummaryModel item) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    try {
      await campaignService.validateUpload(
        tenantId: _tenantId,
        campaignId: item.id,
        bytes: file!.bytes!,
        filename: file.name,
      );
      if (!mounted) return;
      await _load();
      await _openDetail(item.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha validada.')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _startCampaign(CampaignSummaryModel item) async {
    final readiness = _sendReadiness;
    if (readiness != null && !readiness.sendsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(readiness.sendsBlockedReason ?? 'Envio não autorizado.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Confirmar disparo'),
        content: Text(
          'Enviar para ${item.totalRecipients} destinatário(s)?\n\n'
          'Estimativa Meta: ${formatCampaignMetaEstimate(item.metaEstimate)}\n\n'
          '$kCampaignMetaDisclaimer',
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

  bool _canStart(CampaignSummaryModel item) {
    final readiness = _sendReadiness;
    if (readiness == null || !readiness.sendsEnabled) return false;
    return item.totalRecipients > 0 && (item.status == 'validated' || item.status == 'paused');
  }

  @override
  Widget build(BuildContext context) {
    final inset = AppPageInsets.of(context);
    final metrics = _aggregateMetrics();
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;
    final readiness = _sendReadiness;

    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final listPane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          onRefresh: () => _load(),
          onNew: _templates.isEmpty ? null : () => _openWizard(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        CampaignMetricsStrip(
          loading: _loading,
          campaignCount: _items.length,
          sentTotal: metrics.sent,
          deliveredTotal: metrics.delivered,
          deliveryRate: metrics.rate,
          metaEstimateLabel: metrics.metaSum,
        ),
        const SizedBox(height: AppSpacing.md),
        if (readiness != null && !readiness.sendsEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: CampaignSendBlockBanner(
              title: 'Disparos bloqueados pelo plano Atende Ai',
              message: readiness.sendsBlockedReason ?? '',
              onOpenPlan: widget.onOpenBilling,
            ),
          ),
        _FiltersBar(
          search: _search,
          status: _statusFilter,
          sort: _sort,
          onSearch: (v) => setState(() => _search = v),
          onStatus: (v) => setState(() => _statusFilter = v),
          onSort: (v) => setState(() => _sort = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _visibleItems.isEmpty
              ? AppEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Nenhuma campanha',
                  message: 'Crie uma campanha, importe destinatários via XLSX e acompanhe entregas.',
                  action: _templates.isEmpty
                      ? null
                      : FilledButton.icon(
                          onPressed: () => _openWizard(),
                          icon: const Icon(Icons.add),
                          label: const Text('Nova campanha'),
                        ),
                )
              : _CampaignTable(
                  items: _visibleItems,
                  accounts: _accounts,
                  selectedId: _selectedId,
                  onSelect: _openDetail,
                  onImport: _importFor,
                  onWizard: (c) => _openWizard(existing: c, initialStep: 1),
                  onDownloadTemplate: (c) async {
                    final bytes = await campaignService.downloadImportTemplate(
                      tenantId: _tenantId,
                      campaignId: c.id,
                    );
                    _saveBytes(bytes, 'campanha-${c.id}.xlsx');
                  },
                  onDownloadResults: (c) async {
                    final bytes = await campaignService.downloadResults(
                      tenantId: _tenantId,
                      campaignId: c.id,
                    );
                    _saveBytes(bytes, 'resultados-${c.id}.xlsx');
                  },
                  onStart: _canStart,
                  onStartTap: _startCampaign,
                ),
        ),
      ],
    );

    if (!wide) {
      if (_selectedId != null && _detail != null) {
        return Padding(
          padding: inset,
          child: CampaignDetailPanel(
            loading: _detailLoading,
            summary: _detail!.campaign,
            recipients: _detail!.recipients,
            accounts: _accounts,
            sendReadiness: readiness ?? CampaignSendReadinessModel(sendsEnabled: false),
            canStart: _canStart(_detail!.campaign),
            onOpenBilling: widget.onOpenBilling,
            onClose: () => setState(() {
              _selectedId = null;
              _detail = null;
            }),
            onImport: () => _importFor(_detail!.campaign),
            onDownloadTemplate: () async {
              final bytes = await campaignService.downloadImportTemplate(
                tenantId: _tenantId,
                campaignId: _detail!.campaign.id,
              );
              _saveBytes(bytes, 'campanha-${_detail!.campaign.id}.xlsx');
            },
            onDownloadResults: () async {
              final bytes = await campaignService.downloadResults(
                tenantId: _tenantId,
                campaignId: _detail!.campaign.id,
              );
              _saveBytes(bytes, 'resultados-${_detail!.campaign.id}.xlsx');
            },
            onStart: _canStart(_detail!.campaign) ? () => _startCampaign(_detail!.campaign) : null,
            onPause: _detail!.campaign.status == 'running'
                ? () async {
                    await campaignService.pauseCampaign(tenantId: _tenantId, campaignId: _detail!.campaign.id);
                    await _load();
                  }
                : null,
            onCancel: () async {
              await campaignService.cancelCampaign(tenantId: _tenantId, campaignId: _detail!.campaign.id);
              await _load();
            },
          ),
        );
      }
      return Padding(padding: inset, child: listPane);
    }

    return Padding(
      padding: inset,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: listPane),
          if (_selectedId != null) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: CampaignDetailPanel(
                loading: _detailLoading,
                summary: _detail?.campaign ??
                    _items.firstWhere((c) => c.id == _selectedId, orElse: () => _items.first),
                recipients: _detail?.recipients ?? const [],
                accounts: _accounts,
                sendReadiness: readiness ?? CampaignSendReadinessModel(sendsEnabled: false),
                canStart: _detail != null && _canStart(_detail!.campaign),
                onOpenBilling: widget.onOpenBilling,
                onClose: () => setState(() {
                  _selectedId = null;
                  _detail = null;
                }),
                onImport: () {
                  final c = _detail?.campaign;
                  if (c != null) _importFor(c);
                },
                onDownloadTemplate: () async {
                  final id = _detail?.campaign.id ?? _selectedId;
                  if (id == null) return;
                  final bytes = await campaignService.downloadImportTemplate(tenantId: _tenantId, campaignId: id);
                  _saveBytes(bytes, 'campanha-$id.xlsx');
                },
                onDownloadResults: () async {
                  final id = _detail?.campaign.id ?? _selectedId;
                  if (id == null) return;
                  final bytes = await campaignService.downloadResults(tenantId: _tenantId, campaignId: id);
                  _saveBytes(bytes, 'resultados-$id.xlsx');
                },
                onStart: _detail != null && _canStart(_detail!.campaign)
                    ? () => _startCampaign(_detail!.campaign)
                    : null,
                onPause: _detail?.campaign.status == 'running'
                    ? () async {
                        await campaignService.pauseCampaign(
                          tenantId: _tenantId,
                          campaignId: _detail!.campaign.id,
                        );
                        await _load();
                      }
                    : null,
                onCancel: _detail != null
                    ? () async {
                        await campaignService.cancelCampaign(
                          tenantId: _tenantId,
                          campaignId: _detail!.campaign.id,
                        );
                        await _load();
                      }
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CampaignSort { recent, name, status }

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh, this.onNew});
  final VoidCallback onRefresh;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campanhas',
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Gerencie suas campanhas WhatsApp, acompanhe entregas e analise resultados.',
                  style: TextStyle(color: AppColors.textSoft, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onRefresh, tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
          const SizedBox(width: AppSpacing.xs),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('Nova campanha'),
          ),
        ],
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.search,
    required this.status,
    required this.sort,
    required this.onSearch,
    required this.onStatus,
    required this.onSort,
  });

  final String search;
  final String? status;
  final _CampaignSort sort;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onStatus;
  final ValueChanged<_CampaignSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar campanha',
            ),
            onChanged: onSearch,
          ),
        ),
        DropdownButton<String?>(
          value: status,
          hint: const Text('Status'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos os status')),
            DropdownMenuItem(value: 'draft', child: Text('Rascunho')),
            DropdownMenuItem(value: 'validated', child: Text('Validada')),
            DropdownMenuItem(value: 'running', child: Text('Em execução')),
            DropdownMenuItem(value: 'paused', child: Text('Pausada')),
            DropdownMenuItem(value: 'completed', child: Text('Concluída')),
          ],
          onChanged: onStatus,
        ),
        DropdownButton<_CampaignSort>(
          value: sort,
          items: const [
            DropdownMenuItem(value: _CampaignSort.recent, child: Text('Mais recentes')),
            DropdownMenuItem(value: _CampaignSort.name, child: Text('Nome')),
            DropdownMenuItem(value: _CampaignSort.status, child: Text('Status')),
          ],
          onChanged: (v) {
            if (v != null) onSort(v);
          },
        ),
      ],
    );
  }
}

class _CampaignTable extends StatelessWidget {
  const _CampaignTable({
    required this.items,
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
    required this.onImport,
    required this.onWizard,
    required this.onDownloadTemplate,
    required this.onDownloadResults,
    required this.onStart,
    required this.onStartTap,
  });

  final List<CampaignSummaryModel> items;
  final List<WhatsAppAccountModel> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<CampaignSummaryModel> onImport;
  final ValueChanged<CampaignSummaryModel> onWizard;
  final Future<void> Function(CampaignSummaryModel) onDownloadTemplate;
  final Future<void> Function(CampaignSummaryModel) onDownloadResults;
  final bool Function(CampaignSummaryModel) onStart;
  final Future<void> Function(CampaignSummaryModel) onStartTap;

  String _phone(CampaignSummaryModel c) {
    final k = c.accountKey;
    if (k == null) return '—';
    return accounts.where((a) => a.accountKey == k).map((a) => a.displayPhoneNumber).firstOrNull ?? k;
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppBreakpoints.isCompact(context);
    if (compact) {
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (ctx, i) => _CampaignCard(
          item: items[i],
          phone: _phone(items[i]),
          selected: items[i].id == selectedId,
          onTap: () => onSelect(items[i].id),
          onImport: () => onImport(items[i]),
          onWizard: () => onWizard(items[i]),
          onDownloadTemplate: () => onDownloadTemplate(items[i]),
          onStart: onStart(items[i]) ? () => onStartTap(items[i]) : null,
        ),
      );
    }
    return Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 48),
          child: DataTable(
            headingTextStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            dataTextStyle: const TextStyle(color: AppColors.text, fontSize: 12),
            columns: const [
              DataColumn(label: Text('Campanha')),
              DataColumn(label: Text('Template')),
              DataColumn(label: Text('Conta')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Dest.')),
              DataColumn(label: Text('Entregues')),
              DataColumn(label: Text('Progresso')),
              DataColumn(label: Text('Ações')),
            ],
            rows: items.map((c) {
              final selected = c.id == selectedId;
              return DataRow(
                selected: selected,
                onSelectChanged: (_) => onSelect(c.id),
                cells: [
                  DataCell(Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(c.templateName)),
                  DataCell(Text(_phone(c))),
                  DataCell(CampaignStatusBadge(status: c.status, compact: true)),
                  DataCell(Text('${c.totalRecipients}')),
                  DataCell(Text('${c.deliveredCount + c.readCount}')),
                  DataCell(SizedBox(width: 120, child: CampaignProgressBar(item: c))),
                  DataCell(
                    PopupMenuButton<String>(
                      tooltip: 'Ações',
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'detail', child: Text('Ver detalhes')),
                        const PopupMenuItem(value: 'import', child: Text('Importar destinatários')),
                        const PopupMenuItem(value: 'model', child: Text('Baixar modelo Excel')),
                        const PopupMenuItem(value: 'wizard', child: Text('Assistente de configuração')),
                        if (onStart(c))
                          const PopupMenuItem(value: 'start', child: Text('Iniciar campanha')),
                        const PopupMenuItem(value: 'export', child: Text('Exportar resultados')),
                      ],
                      onSelected: (v) async {
                        switch (v) {
                          case 'detail':
                            onSelect(c.id);
                          case 'import':
                            onImport(c);
                          case 'model':
                            await onDownloadTemplate(c);
                          case 'wizard':
                            onWizard(c);
                          case 'start':
                            await onStartTap(c);
                          case 'export':
                            await onDownloadResults(c);
                        }
                      },
                      child: const Icon(Icons.more_horiz),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.item,
    required this.phone,
    required this.selected,
    required this.onTap,
    required this.onImport,
    required this.onWizard,
    required this.onDownloadTemplate,
    this.onStart,
  });

  final CampaignSummaryModel item;
  final String phone;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onImport;
  final VoidCallback onWizard;
  final VoidCallback onDownloadTemplate;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryMuted : AppColors.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                CampaignStatusBadge(status: item.status, compact: true),
              ],
            ),
            Text('$phone · ${item.templateName}', style: const TextStyle(color: AppColors.textSoft, fontSize: 11)),
            const SizedBox(height: AppSpacing.sm),
            CampaignProgressBar(item: item),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                TextButton(onPressed: onImport, child: const Text('Importar')),
                TextButton(onPressed: onDownloadTemplate, child: const Text('Modelo')),
                TextButton(onPressed: onWizard, child: const Text('Assistente')),
                if (onStart != null)
                  FilledButton(onPressed: onStart, child: const Text('Iniciar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}