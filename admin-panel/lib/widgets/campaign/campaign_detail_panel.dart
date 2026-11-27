import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/campaign.dart';
import '../../models/whatsapp_account.dart';
import '../../theme/app_tokens.dart';
import '../../utils/campaign_format.dart';
import 'campaign_ui.dart';

class CampaignDetailPanel extends StatelessWidget {
  const CampaignDetailPanel({
    super.key,
    required this.loading,
    required this.summary,
    required this.recipients,
    required this.accounts,
    required this.onImport,
    required this.onDownloadTemplate,
    required this.onDownloadResults,
    required this.onStart,
    required this.onPause,
    required this.onCancel,
    required this.onClose,
    required this.sendReadiness,
    this.onOpenBilling,
    this.canStart = false,
    this.fullPage = false,
  });

  final bool loading;
  final CampaignSummaryModel summary;
  final List<CampaignRecipientRowModel> recipients;
  final List<WhatsAppAccountModel> accounts;
  final CampaignSendReadinessModel sendReadiness;
  final VoidCallback onImport;
  final VoidCallback onDownloadTemplate;
  final VoidCallback onDownloadResults;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;
  final VoidCallback onClose;
  final VoidCallback? onOpenBilling;
  final bool canStart;
  final bool fullPage;

  String _accountLabel() {
    final key = summary.accountKey;
    if (key == null) return '—';
    final match = accounts.where((a) => a.accountKey == key).firstOrNull;
    return match?.displayPhoneNumber ?? key;
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.name,
                        style: GoogleFonts.manrope(
                          fontSize: fullPage ? 22 : 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    CampaignStatusBadge(status: summary.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${summary.templateName} · ${_accountLabel()} · ${summary.templateCategory}',
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                ),
                if (summary.createdAt != null)
                  Text(
                    'Criada em ${formatCampaignDate(summary.createdAt)}',
                    style: const TextStyle(color: AppColors.textSoft, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (!fullPage)
            IconButton(onPressed: onClose, tooltip: 'Fechar', icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  Widget _bodySections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: CampaignProgressBar(item: summary),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _metricChip('Destinatários', summary.totalRecipients),
              _metricChip('Enviadas', summary.messagesSent),
              _metricChip('Entregues', summary.messagesDelivered),
              _metricChip('Lidas', summary.readCount),
              _metricChip('Falhas', summary.failedCount),
              if (summary.pendingCount > 0) _metricChip('Pendentes', summary.pendingCount),
              if (summary.uncertainCount > 0) _metricChip('Incertas', summary.uncertainCount),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            '${campaignMetaEstimateIsActual(summary.metaEstimate) ? 'Custo estimado Meta' : 'Previsão Meta'}: ${formatCampaignMetaEstimate(summary.metaEstimate)}',
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (!sendReadiness.sendsEnabled) ...[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: CampaignSendBlockBanner(
              title: 'Envio não autorizado',
              message: sendReadiness.sendsBlockedReason ?? '',
              onOpenPlan: onOpenBilling,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (!const {'completed', 'cancelled', 'canceled'}.contains(summary.status)) ...[
                OutlinedButton.icon(
                  onPressed: onDownloadTemplate,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Modelo XLSX'),
                ),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Importar'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: onDownloadResults,
                icon: const Icon(Icons.table_view, size: 18),
                label: const Text('Exportar'),
              ),
              if (canStart && onStart != null)
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar'),
                ),
              if (summary.status == 'running' && onPause != null)
                OutlinedButton.icon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
              if (onCancel != null &&
                  const {'draft', 'validated', 'paused'}.contains(summary.status))
                TextButton(onPressed: onCancel, child: const Text('Cancelar campanha')),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        _RecipientsTable(recipients: recipients, embedded: !fullPage),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(kCampaignMetaDisclaimer, style: const TextStyle(color: AppColors.textSoft, fontSize: 10)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
    }

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        _bodySections(),
      ],
    );

    final shell = Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    if (!fullPage) {
      return shell;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fullPage)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TextButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back, size: 20),
              label: const Text('Voltar para campanhas'),
            ),
          ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: shell,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricChip(String label, int value) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 11)),
      backgroundColor: AppColors.surfaceAlt,
      side: const BorderSide(color: AppColors.border),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RecipientsTable extends StatefulWidget {
  const _RecipientsTable({required this.recipients, this.embedded = false});
  final List<CampaignRecipientRowModel> recipients;
  final bool embedded;

  @override
  State<_RecipientsTable> createState() => _RecipientsTableState();
}

class _RecipientsTableState extends State<_RecipientsTable> {
  String _query = '';
  String? _status;

  @override
  Widget build(BuildContext context) {
    var rows = widget.recipients;
    if (_status != null) rows = rows.where((r) => r.status == _status).toList();
    if (_query.isNotEmpty) {
      rows = rows.where((r) => r.phone.contains(_query)).toList();
    }

    final list = rows.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('Nenhum destinatário', style: TextStyle(color: AppColors.textSoft)),
          )
        : ListView.separated(
            shrinkWrap: !widget.embedded,
            physics: widget.embedded
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (ctx, i) {
              final r = rows[i];
              return ListTile(
                dense: true,
                title: Text(r.phone, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  [
                    recipientStatusLabel(r.status),
                    if (r.bodyParams.isNotEmpty)
                      r.bodyParams.entries.map((e) => '${e.key}: ${e.value}').join(' · '),
                    if (r.errorMessage != null) r.errorMessage!,
                  ].where((p) => p.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                trailing: Text(
                  formatCampaignDate(r.deliveredAt ?? r.sentAt),
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 10),
                ),
              );
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Buscar telefone',
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<String?>(
                value: _status,
                hint: const Text('Status', style: TextStyle(fontSize: 12)),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'pending', child: Text('Pendente')),
                  DropdownMenuItem(value: 'sent', child: Text('Enviada')),
                  DropdownMenuItem(value: 'delivered', child: Text('Entregue')),
                  DropdownMenuItem(value: 'failed', child: Text('Falhou')),
                  DropdownMenuItem(value: 'uncertain', child: Text('Incerta')),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ],
          ),
        ),
        if (widget.embedded)
          Expanded(child: list)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120),
            child: list,
          ),
      ],
    );
  }
}