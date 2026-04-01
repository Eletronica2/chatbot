import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_overview.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';

const _kBg = Color(0xFF0B1120);
const _kSurface = Color(0xFF111827);
const _kCard = Color(0xFF182235);
const _kCardAlt = Color(0xFF0F172A);
const _kBorder = Color(0xFF243041);
const _kText = Color(0xFFE2E8F0);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kAccent = Color(0xFF7C8CFF);
const _kSuccess = Color(0xFF10B981);
const _kDanger = Color(0xFFEF4444);

String _overviewPlanLabel(String value) {
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

String _overviewStatusLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'active':
      return 'Ativo';
    case 'trialing':
      return 'Em teste';
    case 'past_due':
      return 'Pagamento pendente';
    case 'canceled':
      return 'Cancelado';
    case 'inactive':
      return 'Inativo';
    case 'invited':
      return 'Convidado';
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

String _overviewRoleLabel(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.contains('system')) return 'Administrador do sistema';
  if (normalized.contains('super')) return 'Superadministrador';
  if (normalized.contains('owner')) return 'Proprietário';
  if (normalized.contains('manager')) return 'Gerente';
  if (normalized.contains('agent')) return 'Atendente';
  return 'Usuário';
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.onOpenConversations,
    required this.onOpenFlows,
    required this.onOpenBilling,
    this.onOpenBackoffice,
  });

  final VoidCallback onOpenConversations;
  final VoidCallback onOpenFlows;
  final VoidCallback onOpenBilling;
  final VoidCallback? onOpenBackoffice;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<DashboardOverviewModel> _future;

  @override
  void initState() {
    super.initState();
    _future = dashboardService.fetchOverview();
  }

  void _refresh() {
    setState(() {
      _future = dashboardService.fetchOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: FutureBuilder<DashboardOverviewModel>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _OverviewErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final overview = snapshot.data;
          if (overview == null) {
            return _OverviewErrorState(
              message: 'Nenhum dado do painel foi retornado.',
              onRetry: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroPanel(
                    overview: overview,
                    onOpenConversations: widget.onOpenConversations,
                    onOpenFlows: widget.onOpenFlows,
                    onOpenBilling: widget.onOpenBilling,
                    onOpenBackoffice: widget.onOpenBackoffice,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: overview.kpis
                        .map((item) => _KpiCard(kpi: item))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 1180;
                      final left = _PlansPanel(
                        overview: overview,
                        onOpenBilling: widget.onOpenBilling,
                      );
                      final right = _RecentEventsPanel(
                        events: overview.recentEvents,
                      );

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
                  if (overview.topTenants.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _TopTenantsPanel(
                      items: overview.topTenants,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.overview,
    required this.onOpenConversations,
    required this.onOpenFlows,
    required this.onOpenBilling,
    this.onOpenBackoffice,
  });

  final DashboardOverviewModel overview;
  final VoidCallback onOpenConversations;
  final VoidCallback onOpenFlows;
  final VoidCallback onOpenBilling;
  final VoidCallback? onOpenBackoffice;

  @override
  Widget build(BuildContext context) {
    final activeTenant = authService.tenantId ?? overview.tenantId ?? 'default';
    final canOpenBackoffice = onOpenBackoffice != null && authService.isSuperadmin;
    final scopeLabel = overview.scope == 'global'
        ? 'Visão global da plataforma'
        : 'Visão operacional do cliente';

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
            color: Color(0x24000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 960;
          final actions = Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _HeroAction(
                label: 'Conversas',
                helper: 'Atendimento em tempo real',
                icon: Icons.chat_bubble_outline_rounded,
                onTap: onOpenConversations,
              ),
              _HeroAction(
                label: 'Fluxos',
                helper: 'Editar automações',
                icon: Icons.account_tree_outlined,
                onTap: onOpenFlows,
              ),
              _HeroAction(
                label: 'Cobrança',
                helper: 'Planos e pagamentos',
                icon: Icons.credit_card_rounded,
                onTap: onOpenBilling,
              ),
              if (canOpenBackoffice)
                _HeroAction(
                  label: 'Administração',
                  helper: 'Clientes e operação',
                  icon: Icons.apartment_rounded,
                  onTap: onOpenBackoffice!,
                ),
            ],
          );

          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x221E293B),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  scopeLabel,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                overview.tenantName ?? 'Operação do chatbot',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                overview.scope == 'global'
                    ? 'Acompanhe crescimento, cobrança e uso dos clientes em uma visão executiva.'
                    : 'Monitore uso, automação, assinatura e desempenho do atendimento deste cliente.',
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InlineBadge(
                    icon: Icons.hub_rounded,
                    label: 'Cliente em foco: $activeTenant',
                  ),
                  _InlineBadge(
                    icon: Icons.security_rounded,
                    label: 'Perfil: ${_overviewRoleLabel(authService.currentUser?.role)}',
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                intro,
                const SizedBox(height: 24),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: intro),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final DashboardKpiModel kpi;

  @override
  Widget build(BuildContext context) {
    final toneColor = switch (kpi.tone) {
      'success' => _kSuccess,
      'danger' => _kDanger,
      'accent' => _kAccent,
      _ => const Color(0xFF38BDF8),
    };

    return Container(
      width: 260,
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
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: toneColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            kpi.label,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            kpi.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (kpi.helper != null && kpi.helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              kpi.helper!,
              style: const TextStyle(
                color: _kSubtle,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlansPanel extends StatelessWidget {
  const _PlansPanel({
    required this.overview,
    required this.onOpenBilling,
  });

  final DashboardOverviewModel overview;
  final VoidCallback onOpenBilling;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Uso por plano',
      subtitle: overview.scope == 'global'
          ? 'Distribuição comercial e receita estimada dos clientes.'
          : 'Resumo do plano atual deste cliente.',
      action: TextButton.icon(
        onPressed: onOpenBilling,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('Abrir cobrança'),
      ),
      child: overview.planBreakdown.isEmpty
          ? const _EmptyPanelMessage(
              message: 'Nenhum dado de plano disponível no momento.',
            )
          : Column(
              children: overview.planBreakdown.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kCardAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _overviewPlanLabel(item.plan),
                                style: const TextStyle(
                                  color: _kText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.tenants} cliente(s)',
                                style: const TextStyle(
                                  color: _kSubtle,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatMoney(item.estimatedMrrCents),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
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

  String _formatMoney(int cents) {
    final value = cents / 100;
    return NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    ).format(value);
  }
}

class _RecentEventsPanel extends StatelessWidget {
  const _RecentEventsPanel({required this.events});

  final List<DashboardRecentEventModel> events;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Eventos recentes',
      subtitle: 'Tudo que mudou por último em usuários, fluxos, clientes e cobrança.',
      child: events.isEmpty
          ? const _EmptyPanelMessage(
              message: 'Nenhum evento recente foi encontrado.',
            )
          : Column(
              children: events.map((event) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
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
                                event.summary,
                                style: const TextStyle(
                                  color: _kText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              _formatDateTime(event.createdAt),
                              style: const TextStyle(
                                color: _kSubtle,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${event.action}  •  ${event.actorEmail ?? 'sistema'}  •  ${event.tenantId}',
                          style: const TextStyle(
                            color: _kMuted,
                            fontSize: 12,
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

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'agora';
    return DateFormat('dd/MM HH:mm').format(value.toLocal());
  }
}

class _TopTenantsPanel extends StatelessWidget {
  const _TopTenantsPanel({required this.items});

  final List<DashboardTopTenantModel> items;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Clientes com maior uso',
      subtitle: 'Visão rápida de quem mais consome mensagens no período atual.',
      child: Column(
        children: items.map((item) {
          final limit = item.monthlyMessageLimit <= 0 ? 1 : item.monthlyMessageLimit;
          final usage = (item.usedMessages / limit).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCardAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.tenantName,
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.tenantId} • ${_overviewPlanLabel(item.plan)} • ${_overviewStatusLabel(item.status)}',
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${item.usedMessages}/${item.monthlyMessageLimit}',
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
                      minHeight: 8,
                      value: usage,
                      backgroundColor: const Color(0xFF1E293B),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usage > 0.85 ? _kDanger : _kAccent,
                      ),
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
}

class _HeroAction extends StatefulWidget {
  const _HeroAction({
    required this.label,
    required this.helper,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String helper;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeroAction> createState() => _HeroActionState();
}

class _HeroActionState extends State<_HeroAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0x201E293B)
                  : const Color(0x141E293B),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    _hovered ? const Color(0xFF475569) : const Color(0xFF334155),
              ),
              boxShadow: _hovered
                  ? const [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.icon, color: _kAccent, size: 20),
                const SizedBox(height: 12),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.helper,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x141E293B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _kMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _kText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 12),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardAlt,
        borderRadius: BorderRadius.circular(18),
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

class _OverviewErrorState extends StatelessWidget {
  const _OverviewErrorState({
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
            const Icon(Icons.insights_rounded, size: 42, color: _kMuted),
            const SizedBox(height: 14),
            const Text(
              'Não foi possível carregar o painel',
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

