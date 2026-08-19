import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/billing_summary.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

const _kSurface = AppColors.surface;
const _kCard = AppColors.surfaceAlt;
const _kCardAlt = AppColors.surfaceSoft;
const _kBorder = AppColors.border;
const _kText = AppColors.text;
const _kMuted = AppColors.textMuted;
const _kSubtle = AppColors.textSoft;
const _kAccent = AppColors.primary;
const _kSuccess = AppColors.success;
const _kDanger = AppColors.danger;

String _billingPlanLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'starter':
      return 'Inicial';
    case 'growth':
      return 'Crescimento';
    case 'pro':
      return 'Profissional';
    case 'enterprise':
      return 'Empresarial';
    default:
      return value.isEmpty ? 'Plano' : value;
  }
}

String _billingStatusLabel(String value) {
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
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

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

  @override
  void initState() {
    super.initState();
    _future = _loadSummary();
  }

  Future<BillingSummaryModel> _loadSummary() {
    return billingService.fetchSummary();
  }

  void _refresh() {
    setState(() {
      _future = _loadSummary();
    });
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
        _showSnack('Não foi possível abrir a página de pagamento.', isError: true);
      }
      _refresh();
    } catch (err) {
      if (mounted) {
        _showSnack('Não foi possível iniciar o pagamento: $err', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingPlan = null);
      }
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
        _showSnack('Não foi possível abrir o portal de cobrança.', isError: true);
      }
      _refresh();
    } catch (err) {
      if (mounted) {
        _showSnack('Não foi possível abrir o portal: $err', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _openingPortal = false);
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _kDanger : _kSuccess,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSystemHomeContext) {
      return PremiumPageBackground(
        intensity: AmbientIntensity.soft,
        child: _SystemBillingState(onOpenBackoffice: widget.onOpenBackoffice),
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
            return _BillingErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final summary = snapshot.data;
          if (summary == null) {
            return _BillingErrorState(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BillingHero(
                    summary: summary,
                    onOpenPortal: summary.customer?.providerCustomerId.isNotEmpty == true
                        ? _openPortal
                        : null,
                    openingPortal: _openingPortal,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _BillingMetricCard(
                        label: 'Plano atual',
                        value: _billingPlanLabel(summary.currentPlan),
                        helper: _billingStatusLabel(summary.subscriptionStatus),
                      ),
                      _BillingMetricCard(
                        label: 'Renovação',
                        value: _formatDate(summary.renewalDate),
                        helper: '${summary.graceDays} dias de tolerância após vencimento',
                      ),
                      _BillingMetricCard(
                        label: 'Mensagens usadas',
                        value: '${summary.usedMessages}',
                        helper: 'de ${summary.monthlyMessageLimit} no período atual',
                      ),
                      _BillingMetricCard(
                        label: 'Mensagens restantes',
                        value: '${summary.remainingMessages}',
                        helper: 'Capacidade disponível no plano',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 1160;
                      final left = _PlansCatalogPanel(
                        summary: summary,
                        loadingPlan: _loadingPlan,
                        onOpenCheckout: _openCheckout,
                      );
                      final right = _InvoicesPanel(summary: summary);

                      if (stacked) {
                        return Column(
                          children: [
                            left,
                            const SizedBox(height: 16),
                            right,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: right),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Não informado';
    return DateFormat('dd/MM/yyyy').format(value.toLocal());
  }
}

class _SystemBillingState extends StatelessWidget {
  const _SystemBillingState({this.onOpenBackoffice});

  final VoidCallback? onOpenBackoffice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment_rounded, size: 46, color: _kAccent),
            const SizedBox(height: 18),
            const Text(
              'Selecione um cliente para ver a cobrança',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A conta system-admin não possui assinatura própria. Escolha um cliente na administração SaaS para acompanhar plano, faturas e pagamento.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (onOpenBackoffice != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenBackoffice,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Abrir administração SaaS'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BillingHero extends StatelessWidget {
  const _BillingHero({
    required this.summary,
    this.onOpenPortal,
    required this.openingPortal,
  });

  final BillingSummaryModel summary;
  final VoidCallback? onOpenPortal;
  final bool openingPortal;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (summary.subscriptionStatus) {
      'active' => _kSuccess,
      'trialing' => const Color(0xFFF59E0B),
      'past_due' => _kDanger,
      'canceled' => const Color(0xFF64748B),
      _ => _kMuted,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
        gradient: const LinearGradient(
          colors: [Color(0xFF182235), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'Status: ${_billingStatusLabel(summary.subscriptionStatus)}',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cobrança e assinatura',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary.providerReady
                    ? 'Gerencie upgrade, downgrade, portal de pagamento e faturas do cliente.'
                    : 'O provedor de cobrança ainda não está configurado. Você pode acompanhar uso e plano atual, mas o pagamento e o portal seguem indisponíveis.',
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          );

          final side = Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              if (summary.customer != null &&
                  summary.customer!.providerCustomerId.isNotEmpty)
                _SmallPill(
                  label: 'Cliente no provedor: ${summary.customer!.providerCustomerId}',
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onOpenPortal == null || openingPortal ? null : onOpenPortal,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(openingPortal ? 'Abrindo...' : 'Portal de cobrança'),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                intro,
                const SizedBox(height: 20),
                side,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: intro),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: side),
            ],
          );
        },
      ),
    );
  }
}

class _PlansCatalogPanel extends StatelessWidget {
  const _PlansCatalogPanel({
    required this.summary,
    required this.loadingPlan,
    required this.onOpenCheckout,
  });

  final BillingSummaryModel summary;
  final String? loadingPlan;
  final ValueChanged<String> onOpenCheckout;

  @override
  Widget build(BuildContext context) {
    final plans = summary.availablePlans.isEmpty
        ? const ['starter', 'growth', 'pro', 'enterprise']
        : summary.availablePlans;

    return _PanelCard(
      title: 'Catálogo de planos',
      subtitle:
          'Use a página de pagamento para upgrade, downgrade ou reativação. O status em atraso bloqueia o processamento após a janela de tolerância.',
      child: Column(
        children: plans.map((plan) {
          final isCurrent = plan == summary.currentPlan;
          final isLoading = loadingPlan == plan;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isCurrent ? _kCard : _kCardAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isCurrent ? _kAccent : _kBorder,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _billingPlanLabel(plan),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              const _SmallPill(label: 'Atual'),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _planDescription(plan),
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: summary.providerReady && !isLoading
                        ? () => onOpenCheckout(plan)
                        : null,
                    child: Text(
                      isCurrent
                          ? 'Trocar plano'
                          : isLoading
                              ? 'Abrindo...'
                              : 'Contratar plano',
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _planDescription(String plan) {
    switch (plan) {
      case 'growth':
        return 'Para operações em crescimento, com mais mensagens e equipe.';
      case 'pro':
        return 'Ideal para negócios com automações mais intensas e volume alto.';
      case 'enterprise':
        return 'Camada premium para operações com alto volume e governança.';
      default:
        return 'Plano de entrada para validar a operação e os primeiros clientes.';
    }
  }
}

class _InvoicesPanel extends StatelessWidget {
  const _InvoicesPanel({required this.summary});

  final BillingSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    final usagePercent = summary.monthlyMessageLimit <= 0
        ? 0.0
        : (summary.usedMessages / summary.monthlyMessageLimit).clamp(0.0, 1.0);

    return Column(
      children: [
        _PanelCard(
          title: 'Uso do período',
          subtitle: 'Acompanhe a pressão sobre o plano e antecipe upgrades.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${summary.usedMessages} usadas de ${summary.monthlyMessageLimit}',
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${(usagePercent * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: usagePercent,
                  backgroundColor: const Color(0xFF1E293B),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    usagePercent >= 0.9 ? _kDanger : _kAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PanelCard(
          title: 'Faturas recentes',
          subtitle: 'Histórico retornado pelo provedor de cobrança.',
          child: summary.invoices.isEmpty
              ? const _EmptyPanelMessage(
                  message: 'Ainda não existem faturas sincronizadas para este cliente.',
                )
              : Column(
                  children: summary.invoices.map((invoice) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _kCardAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    invoice.providerInvoiceId,
                                    style: const TextStyle(
                                      color: _kText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _SmallPill(label: _billingStatusLabel(invoice.status)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_formatMoney(invoice.amountPaid)} pago de ${_formatMoney(invoice.amountDue)}',
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Criada em ${_formatDate(invoice.createdAt)}  •  Vencimento ${_formatDate(invoice.dueDate)}',
                              style: const TextStyle(
                                color: _kSubtle,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Não informado';
    return DateFormat('dd/MM/yyyy').format(value.toLocal());
  }

  String _formatMoney(int cents) {
    final value = cents / 100;
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    ).format(value);
  }
}

class _BillingMetricCard extends StatelessWidget {
  const _BillingMetricCard({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            style: const TextStyle(
              color: _kSubtle,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x141E293B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  const _EmptyPanelMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: _kMuted,
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}

class _BillingErrorState extends StatelessWidget {
  const _BillingErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.credit_card_off_rounded, size: 42, color: _kMuted),
            const SizedBox(height: 14),
            const Text(
              'Não foi possível carregar a cobrança',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
