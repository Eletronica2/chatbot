import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/subscription_info.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Plano e cobrança — visão do admin do tenant (não superadmin hub).
class BillingPlanScreen extends StatefulWidget {
  const BillingPlanScreen({super.key});

  @override
  State<BillingPlanScreen> createState() => _BillingPlanScreenState();
}

class _BillingPlanScreenState extends State<BillingPlanScreen> {
  SubscriptionInfo? _subscription;
  List<MetaRateCard> _metaRates = const [];
  List<FiscalDocument> _fiscalDocs = const [];
  bool _loading = true;
  String? _error;
  String? _loadingPlan;
  bool _openingPortal = false;

  static const List<_PlanOption> _plans = <_PlanOption>[
    _PlanOption(
      id: 'starter',
      label: 'Starter',
      blurb: 'Ideal para começar o atendimento automatizado.',
    ),
    _PlanOption(
      id: 'growth',
      label: 'Growth',
      blurb: 'Mais volume e operação com equipe.',
    ),
    _PlanOption(
      id: 'on_demand',
      label: 'On-demand',
      blurb: 'Uso sob demanda, sem pacote fixo alto.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final tenantId = authService.tenantId ?? '';
    try {
      final sub = tenantId.isEmpty
          ? null
          : await subscriptionService.fetchSubscription(tenantId);

      List<MetaRateCard> rates = const [];
      try {
        rates = await billingService.fetchMetaRates();
      } catch (_) {
        rates = const [];
      }

      List<FiscalDocument> docs = const [];
      try {
        docs = await billingService.fetchFiscalDocuments();
      } catch (_) {
        docs = const [];
      }

      if (!mounted) return;
      setState(() {
        _subscription = sub;
        _metaRates = rates;
        _fiscalDocs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o plano.';
      });
    }
  }

  Future<void> _changePlan(String plan) async {
    setState(() => _loadingPlan = plan);
    try {
      final session = await billingService.createCheckoutSession(plan);
      final ok = await launchUrl(
        Uri.parse(session.checkoutUrl),
        mode: LaunchMode.platformDefault,
      );
      if (!ok && mounted) {
        _snack('Não foi possível abrir o checkout.', error: true);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _snack(
          'Checkout indisponível no momento. Contate o suporte Atende Ai se precisar alterar o plano.',
          error: true,
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
        _snack('Não foi possível abrir o portal.', error: true);
      }
    } catch (_) {
      if (mounted) {
        _snack(
          'Portal de pagamento ainda não configurado para esta conta.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  String _planLabel(String plan) {
    switch (plan.toLowerCase()) {
      case 'starter':
        return 'Starter';
      case 'growth':
        return 'Growth';
      case 'on_demand':
      case 'ondemand':
      case 'payg':
        return 'On-demand';
      default:
        return plan;
    }
  }

  String _formatMoney(MetaRateCard rate) {
    final fmt = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: rate.currency == 'BRL' ? r'R$' : '${rate.currency} ',
    );
    return fmt.format(rate.rate);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.text)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : _buildContent()),
    );
  }

  Widget _buildContent() {
    final sub = _subscription;
    final current = sub?.plan ?? 'starter';
    final used = sub?.usedMessages ?? 0;
    final limit = sub?.monthlyMessageLimit ?? 0;
    final remaining = sub?.remainingMessages ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'Plano atual',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _planLabel(current),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Status: ${sub?.status ?? '—'}'
                      '${sub?.active == true ? ' · ativo' : ''}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    if (sub?.renewalDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Renovação: ${DateFormat('dd/MM/yyyy').format(sub!.renewalDate!)}',
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Uso do mês (Atende Ai)',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (limit > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (used / limit).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceAlt,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$used / $limit mensagens · $remaining restantes',
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 12,
                        ),
                      ),
                    ] else
                      Text(
                        used > 0
                            ? '$used mensagens registradas neste período'
                            : 'Sem limite mensal informado para este plano.',
                        style: const TextStyle(
                          color: AppColors.textSoft,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Alterar plano',
                child: Column(
                  children: [
                    for (final plan in _plans) ...[
                      _PlanTile(
                        option: plan,
                        selected: current.toLowerCase() == plan.id ||
                            (plan.id == 'on_demand' &&
                                current.toLowerCase().contains('demand')),
                        loading: _loadingPlan == plan.id,
                        onTap: () => _changePlan(plan.id),
                      ),
                      if (plan != _plans.last) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Portal de pagamento',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gerencie cartão, faturas Stripe e dados de cobrança no portal do provedor.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openingPortal ? null : _openPortal,
                      icon: _openingPortal
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(
                        _openingPortal ? 'Abrindo…' : 'Abrir portal',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Custos Meta (WhatsApp)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cobrança da Meta é separada da assinatura Atende Ai. '
                      'Valores abaixo são estimativas por categoria (Brasil), quando disponíveis na API.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_metaRates.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text(
                          'Estimativas Meta ainda não disponíveis. Consulte a documentação oficial da Meta para tarifas atuais.',
                          style: TextStyle(
                            color: AppColors.textSoft,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ..._metaRates.map(
                        (rate) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rate.category,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                _formatMoney(rate),
                                style: const TextStyle(
                                  color: AppColors.primarySoft,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Notas fiscais',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_fiscalDocs.isEmpty ||
                        _fiscalDocs.every((d) => !d.isConfigured))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emissão de NF ainda não configurada',
                              style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Quando a integração fiscal estiver ativa, as notas aparecerão aqui.',
                              style: TextStyle(
                                color: AppColors.textSoft,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._fiscalDocs.map(
                        (doc) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            doc.competence,
                            style: const TextStyle(color: AppColors.text),
                          ),
                          subtitle: Text(
                            doc.status,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          trailing: doc.downloadUrl == null
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.download_rounded),
                                  onPressed: () => launchUrl(
                                    Uri.parse(doc.downloadUrl!),
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanOption {
  const _PlanOption({
    required this.id,
    required this.label,
    required this.blurb,
  });

  final String id;
  final String label;
  final String blurb;
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.option,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final _PlanOption option;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.blurb,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 20)
              else
                const Text(
                  'Selecionar',
                  style: TextStyle(
                    color: AppColors.primarySoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
