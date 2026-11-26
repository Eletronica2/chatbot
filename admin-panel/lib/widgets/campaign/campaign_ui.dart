import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/campaign.dart';
import '../../theme/app_tokens.dart';
import '../../utils/campaign_format.dart';
import '../ui_kit.dart';

class CampaignStatusBadge extends StatelessWidget {
  const CampaignStatusBadge({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        campaignStatusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return AppColors.textMuted;
      case 'validated':
        return AppColors.info;
      case 'running':
        return AppColors.primary;
      case 'paused':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
      case 'canceled':
        return AppColors.textSoft;
      default:
        if (status.contains('fail')) return AppColors.danger;
        return AppColors.textMuted;
    }
  }
}

class CampaignMetricsStrip extends StatelessWidget {
  const CampaignMetricsStrip({
    super.key,
    required this.loading,
    required this.campaignCount,
    this.sentTotal,
    this.deliveredTotal,
    this.deliveryRate,
    this.metaEstimateLabel,
  });

  final bool loading;
  final int campaignCount;
  final int? sentTotal;
  final int? deliveredTotal;
  final double? deliveryRate;
  final String? metaEstimateLabel;

  String _fmtInt(int? v) => v == null ? '—' : '$v';

  String _fmtRate(double? v) {
    if (v == null) return '—';
    return '${(v * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: List.generate(
          4,
          (_) => _SkeletonMetric(),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppMetricCard(
          label: 'Campanhas',
          value: '$campaignCount',
          helper: 'Cadastradas no tenant',
          icon: Icons.campaign_outlined,
          accent: AppColors.primary,
        ),
        AppMetricCard(
          label: 'Mensagens enviadas',
          value: _fmtInt(sentTotal),
          helper: 'Com status enviado ou posterior',
          icon: Icons.send_outlined,
          accent: AppColors.accentBlue,
        ),
        AppMetricCard(
          label: 'Mensagens entregues',
          value: _fmtInt(deliveredTotal),
          helper: 'Entregues ou lidas',
          icon: Icons.done_all_outlined,
          accent: AppColors.success,
        ),
        AppMetricCard(
          label: 'Taxa de entrega',
          value: _fmtRate(deliveryRate),
          helper: 'Entregues ÷ com resultado conhecido',
          icon: Icons.insights_outlined,
          accent: AppColors.accentSecondary,
        ),
        if (metaEstimateLabel != null)
          AppMetricCard(
            label: 'Estimativa Meta',
            value: metaEstimateLabel!,
            helper: 'Soma das campanhas com previsão',
            icon: Icons.payments_outlined,
            accent: AppColors.warning,
          ),
      ],
    );
  }
}

class _SkeletonMetric extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 132,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class CampaignProgressBar extends StatelessWidget {
  const CampaignProgressBar({super.key, required this.item});

  final CampaignSummaryModel item;

  @override
  Widget build(BuildContext context) {
    final total = item.totalRecipients;
    if (total <= 0) {
      return const Text('Sem destinatários', style: TextStyle(color: AppColors.textSoft, fontSize: 12));
    }
    final pending = item.pendingCount;
    final sent = item.sentCount;
    final delivered = item.deliveredCount;
    final read = item.readCount;
    final failed = item.failedCount;
    final uncertain = item.uncertainCount;
    final processed = sent + delivered + read + failed + uncertain;
    final progress = (processed / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.surfaceSoft,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _chip('Pendentes', pending, AppColors.textMuted),
            _chip('Enviadas', sent, AppColors.accentBlue),
            _chip('Entregues', delivered, AppColors.success),
            _chip('Lidas', read, AppColors.primarySoft),
            _chip('Falhas', failed, AppColors.danger),
            _chip('Incertas', uncertain, AppColors.warning),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, int value, Color color) {
    return Text(
      '$label: $value',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
    );
  }
}

class CampaignSendBlockBanner extends StatelessWidget {
  const CampaignSendBlockBanner({
    super.key,
    required this.title,
    required this.message,
    this.onOpenPlan,
  });

  final String title;
  final String message;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: AppColors.warning, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.45)),
                if (onOpenPlan != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: onOpenPlan,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Ver meu plano'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}