import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/billing_summary.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Cobrança — assinatura / uso / catálogo / checkout+portal existentes.
/// API exige superadmin. Não confundir com Assinatura em Clientes (Fase 5).
class BillingHubScreen extends StatefulWidget {
  const BillingHubScreen({
    super.key,
    this.onOpenBackoffice,
  });

  final VoidCallback? onOpenBackoffice;

  @override
  State<BillingHubScreen> createState() => _BillingHubScreenState();
}

class _BillingHubScreenState extends State<BillingHubScreen> {
  late Future<BillingSummaryModel> _future;
  String? _loadingPlan;
  bool _openingPortal = false;

  bool get _isSystemHomeContext =>
      authService.isSuperadmin &&
      authService.tenantId == (authService.homeTenantId ?? '');

  String get _tenantLabel {
    final name = authService.activeTenantDisplayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return authService.tenantId ?? 'tenant';
  }

  @override
  void initState() {
    super.initState();
    _future = billingService.fetchSummary();
  }

  void _refresh() {
    setState(() {
      _future = billingService.fetchSummary();
    });
  }

  Future<void> _confirmAndCheckout(String plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final width = MediaQuery.sizeOf(ctx).width;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: EdgeInsets.symmetric(
            horizontal: width < 420 ? 16 : 24,
            vertical: 24,
          ),
          title: const Text(
            'Abrir pagamento?',
            style: TextStyle(color: AppColors.text),
          ),
          content: SizedBox(
            width: width < 520 ? width - 48 : 400,
            child: Text(
              'Será aberta a página de checkout do provedor para o plano '
              '${_planLabel(plan)}. Nada é cobrado nesta tela — a cobrança '
              'ocorre apenas se o fluxo externo for concluído.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _openCheckout(plan);
  }

  Future<void> _openCheckout(String plan) async {
    setState(() => _loadingPlan = plan);
    try {
      final session = await billingService.createCheckoutSession(plan);
      final ok = await launchUrl(
        Uri.parse(session.checkoutUrl),
        mode: LaunchMode.platformDefault,
      );
      if (!ok && mounted) {
        _showSnack(
          'Não foi possível abrir a página de pagamento.',
          isError: true,
        );
      }
      _refresh();
    } catch (err) {
      if (mounted) {
        _showSnack(
          'Não foi possível iniciar o pagamento: $err',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPlan = null);
    }
  }

  Future<void> _openPortal() async {
    setState(() => _openingPortal = true);
    try {
      final session = await billingService.createPortalSession();
      final ok = await launchUrl(
        Uri.parse(session.portalUrl),
        mode: LaunchMode.platformDefault,
      );
      if (!ok && mounted) {
        _showSnack(
          'Não foi possível abrir o portal de cobrança.',
          isError: true,
        );
      }
      _refresh();
    } catch (err) {
      if (mounted) {
        _showSnack('Não foi possível abrir o portal: $err', isError: true);
      }
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSystemHomeContext) {
      return PremiumPageBackground(
        intensity: AmbientIntensity.soft,
        child: _SystemBillingEmpty(onOpenBackoffice: widget.onOpenBackoffice),
      );
    }

    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: FutureBuilder<BillingSummaryModel>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _BillingError(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final summary = snapshot.data;
          if (summary == null) {
            return _BillingError(
              message: 'Nenhum resumo de cobrança foi retornado.',
              onRetry: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppPageInsets.of(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    tenantLabel: _tenantLabel,
                    summary: summary,
                    openingPortal: _openingPortal,
                    onRefresh: _refresh,
                    onOpenPortal:
                        summary.customer?.providerCustomerId.isNotEmpty == true
                            ? _openPortal
                            : null,
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 960;
                      final planCard = _CurrentPlanCard(summary: summary);
                      final usageCard = _UsageCard(summary: summary);
                      if (stacked) {
                        return Column(
                          children: [
                            planCard,
                            const SizedBox(height: 12),
                            usageCard,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: planCard),
                          const SizedBox(width: 12),
                          Expanded(flex: 5, child: usageCard),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _CatalogCard(
                    summary: summary,
                    loadingPlan: _loadingPlan,
                    onSelectPlan: _confirmAndCheckout,
                  ),
                  const SizedBox(height: 12),
                  _InvoicesCard(summary: summary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Exibe o ID do plano retornado pela API — sem nomenclatura comercial inventada.
String _planLabel(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return 'Plano';
  return raw;
}

String _statusLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'active':
      return 'Ativa';
    case 'trialing':
      return 'Em teste';
    case 'past_due':
      return 'Pagamento pendente';
    case 'canceled':
      return 'Cancelada';
    case 'inactive':
      return 'Inativa';
    case 'paid':
      return 'Paga';
    case 'open':
      return 'Em aberto';
    case 'draft':
      return 'Rascunho';
    case 'void':
      return 'Anulada';
    case 'uncollectible':
      return 'Incobrável';
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

Color _statusColor(String value) {
  switch (value.trim().toLowerCase()) {
    case 'active':
    case 'paid':
      return AppColors.success;
    case 'trialing':
      return AppColors.warning;
    case 'past_due':
    case 'uncollectible':
      return AppColors.danger;
    case 'canceled':
    case 'inactive':
    case 'void':
      return AppColors.textMuted;
    default:
      return AppColors.textSoft;
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Não informado';
  return DateFormat('dd/MM/yyyy').format(value.toLocal());
}

String _formatMoney(int cents, String currency) {
  final code = currency.trim().toLowerCase();
  final locale = code == 'brl' ? 'pt_BR' : 'en_US';
  final symbol = code == 'brl'
      ? 'R\$'
      : code == 'usd'
          ? '\$'
          : code.toUpperCase();
  return NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 2,
  ).format(cents / 100);
}

/// Percentual visual derivado de used/limit (não vem como campo da API).
double _usageRatio(BillingSummaryModel summary) {
  if (summary.monthlyMessageLimit <= 0) return 0;
  final ratio = summary.usedMessages / summary.monthlyMessageLimit;
  if (ratio.isNaN || ratio.isInfinite) return 0;
  if (ratio < 0) return 0;
  if (ratio > 1) return 1;
  return ratio;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tenantLabel,
    required this.summary,
    required this.openingPortal,
    required this.onRefresh,
    this.onOpenPortal,
  });

  final String tenantLabel;
  final BillingSummaryModel summary;
  final bool openingPortal;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenPortal;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 800;
    final status = summary.subscriptionStatus;
    final color = _statusColor(status);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cobrança',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Qual é o plano e o uso de $tenantLabel?',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              label: _statusLabel(status),
              color: color,
            ),
            _Pill(
              label: summary.providerReady
                  ? 'Provedor pronto (${summary.provider})'
                  : 'Provedor indisponível',
              color: summary.providerReady
                  ? AppColors.primary
                  : AppColors.textMuted,
            ),
          ],
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (onOpenPortal != null)
          FilledButton.icon(
            onPressed: openingPortal ? null : onOpenPortal,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(openingPortal ? 'Abrindo…' : 'Portal de cobrança'),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 12), actions],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                actions,
              ],
            ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.summary});

  final BillingSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plano atual',
            style: TextStyle(
              color: AppColors.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _planLabel(summary.currentPlan),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          _KV('Status', _statusLabel(summary.subscriptionStatus)),
          _KV('Renovação', _formatDate(summary.renewalDate)),
          if (summary.graceDays > 0)
            _KV(
              'Tolerância',
              '${summary.graceDays} dia${summary.graceDays == 1 ? '' : 's'} após vencimento',
            ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.summary});

  final BillingSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    final ratio = _usageRatio(summary);
    final over = summary.monthlyMessageLimit > 0 &&
        summary.usedMessages > summary.monthlyMessageLimit;
    final barColor = over || ratio >= 0.9 ? AppColors.danger : AppColors.primary;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uso do ciclo',
            style: TextStyle(
              color: AppColors.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.monthlyMessageLimit <= 0
                ? '${summary.usedMessages} mensagens'
                : '${summary.usedMessages} de ${summary.monthlyMessageLimit}',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary.monthlyMessageLimit <= 0
                ? 'Limite mensal não informado'
                : '${summary.remainingMessages} restantes · '
                    '${(ratio * 100).toStringAsFixed(0)}% do limite',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              minHeight: 10,
              value: summary.monthlyMessageLimit <= 0 ? 0 : ratio,
              backgroundColor: AppColors.surfaceSoft,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          if (over) ...[
            const SizedBox(height: 8),
            const Text(
              'Uso acima do limite do plano.',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.summary,
    required this.loadingPlan,
    required this.onSelectPlan,
  });

  final BillingSummaryModel summary;
  final String? loadingPlan;
  final ValueChanged<String> onSelectPlan;

  @override
  Widget build(BuildContext context) {
    final plans = summary.availablePlans;
    final compact = MediaQuery.sizeOf(context).width < 800;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Planos disponíveis',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary.providerReady
                ? 'Contratar ou trocar abre o checkout do provedor configurado.'
                : 'Catálogo visível; checkout indisponível enquanto o provedor não estiver pronto.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (plans.isEmpty)
            const Text(
              'Nenhum plano retornado pela API.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else
            ...plans.map((plan) {
              final isCurrent =
                  plan.trim().toLowerCase() ==
                  summary.currentPlan.trim().toLowerCase();
              final loading = loadingPlan == plan;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: EdgeInsets.all(compact ? 12 : 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: AppRadius.md,
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.primary.withValues(alpha: 0.45)
                          : AppColors.border,
                    ),
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _planLabel(plan),
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  const _Pill(
                                    label: 'Plano atual',
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: summary.providerReady && !loading
                                  ? () => onSelectPlan(plan)
                                  : null,
                              child: Text(
                                loading
                                    ? 'Abrindo…'
                                    : isCurrent
                                        ? 'Trocar / renovar'
                                        : 'Contratar',
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _planLabel(plan),
                                        style: const TextStyle(
                                          color: AppColors.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (isCurrent) ...[
                                        const SizedBox(width: 8),
                                        const _Pill(
                                          label: 'Plano atual',
                                          color: AppColors.primary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: summary.providerReady && !loading
                                  ? () => onSelectPlan(plan)
                                  : null,
                              child: Text(
                                loading
                                    ? 'Abrindo…'
                                    : isCurrent
                                        ? 'Trocar / renovar'
                                        : 'Contratar',
                              ),
                            ),
                          ],
                        ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _InvoicesCard extends StatelessWidget {
  const _InvoicesCard({required this.summary});

  final BillingSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Faturas',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Histórico retornado pelo provedor para este tenant.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (summary.invoices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: AppRadius.md,
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Nenhuma fatura sincronizada para este cliente.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else
            ...summary.invoices.map((invoice) {
              final color = _statusColor(invoice.status);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              invoice.providerInvoiceId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          _Pill(
                            label: _statusLabel(invoice.status),
                            color: color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_formatMoney(invoice.amountPaid, invoice.currency)} pago · '
                        '${_formatMoney(invoice.amountDue, invoice.currency)} devido',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Criada ${_formatDate(invoice.createdAt)} · '
                        'Venc. ${_formatDate(invoice.dueDate)}',
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SystemBillingEmpty extends StatelessWidget {
  const _SystemBillingEmpty({this.onOpenBackoffice});

  final VoidCallback? onOpenBackoffice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _SurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.apartment_rounded,
                  size: 40,
                  color: AppColors.primarySoft,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Selecione um cliente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A conta administrativa do sistema não possui assinatura própria. '
                  'Abra Clientes, escolha uma empresa e volte à Cobrança para ver '
                  'plano, uso e faturas daquele tenant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (onOpenBackoffice != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onOpenBackoffice,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Abrir Clientes'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingError extends StatelessWidget {
  const _BillingError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _SurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.credit_card_off_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Não foi possível carregar a cobrança',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.hoverOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSoft,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
