import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/conversation.dart';
import '../models/dashboard_overview.dart';
import '../models/subscription_info.dart';
import '../models/whatsapp_account.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../services/dashboard_service.dart';
import '../services/subscription_service.dart';
import '../services/whatsapp_account_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/operation_hub_panel.dart';
import '../widgets/premium_ui.dart';
import '../widgets/ui_kit.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.onOpenConversations,
    required this.onOpenAutomations,
    this.onOpenWhatsApp,
    this.onOpenBilling,
    this.onOpenClients,
    this.onOpenTeam,
  });

  final VoidCallback onOpenConversations;
  final VoidCallback onOpenAutomations;
  final VoidCallback? onOpenWhatsApp;
  final VoidCallback? onOpenBilling;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenTeam;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<_OverviewData> _future;

  String get _tenantId => authService.tenantId ?? 'default';

  bool get _isSystemHomeContext =>
      authService.isSuperadmin &&
      _tenantId == (authService.homeTenantId ?? '');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OverviewData> _load() async {
    if (_isSystemHomeContext) {
      final overview = await dashboardService.fetchOverview();
      return _OverviewData.saas(overview: overview);
    }

    final results = await Future.wait<dynamic>([
      dashboardService.fetchOverview(),
      conversationService.fetchConversations(),
      subscriptionService.fetchSubscription(_tenantId),
      whatsAppAccountService.listAccounts(_tenantId),
    ]);

    return _OverviewData.tenant(
      overview: results[0] as DashboardOverviewModel,
      conversations: results[1] as List<Conversation>,
      subscription: results[2] as SubscriptionInfo,
      whatsappAccounts: results[3] as List<WhatsAppAccountModel>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: FutureBuilder<_OverviewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _OverviewSkeleton();
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Não foi possível carregar a visão geral',
              message:
                  'A consulta falhou. Verifique a conexão e tente de novo.',
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return AppEmptyState(
              icon: Icons.dashboard_outlined,
              title: 'Sem dados',
              message: 'Nenhum dado retornado para este contexto.',
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: AppColors.primary,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppPageInsets.of(context),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: _FadeIn(
                      child: data.isSaasHome
                          ? _SaasOverview(
                              data: data,
                              maxWidth: constraints.maxWidth,
                              onOpenClients: widget.onOpenClients,
                              onOpenBilling: widget.onOpenBilling,
                            )
                          : _TenantOverview(
                              data: data,
                              maxWidth: constraints.maxWidth,
                              onOpenConversations: widget.onOpenConversations,
                              onOpenAutomations: widget.onOpenAutomations,
                              onOpenWhatsApp: widget.onOpenWhatsApp,
                              onOpenTeam: widget.onOpenTeam,
                            ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OverviewData {
  const _OverviewData._({
    required this.overview,
    required this.conversations,
    required this.whatsappAccounts,
    required this.isSaasHome,
    this.subscription,
  });

  factory _OverviewData.saas({required DashboardOverviewModel overview}) {
    return _OverviewData._(
      overview: overview,
      conversations: const [],
      whatsappAccounts: const [],
      isSaasHome: true,
    );
  }

  factory _OverviewData.tenant({
    required DashboardOverviewModel overview,
    required List<Conversation> conversations,
    required SubscriptionInfo subscription,
    required List<WhatsAppAccountModel> whatsappAccounts,
  }) {
    return _OverviewData._(
      overview: overview,
      conversations: conversations,
      subscription: subscription,
      whatsappAccounts: whatsappAccounts,
      isSaasHome: false,
    );
  }

  final DashboardOverviewModel overview;
  final List<Conversation> conversations;
  final SubscriptionInfo? subscription;
  final List<WhatsAppAccountModel> whatsappAccounts;
  final bool isSaasHome;

  int get waitingConversations =>
      conversations.where((c) => c.unreadCount > 0).length;

  DashboardKpiModel? kpiContaining(String needle) {
    final n = needle.toLowerCase();
    for (final item in overview.kpis) {
      if (item.label.toLowerCase().contains(n)) return item;
    }
    return null;
  }

  WhatsAppAccountModel? get defaultWhatsApp {
    for (final item in whatsappAccounts) {
      if (item.isDefault) return item;
    }
    return whatsappAccounts.isNotEmpty ? whatsappAccounts.first : null;
  }
}

class _SaasOverview extends StatelessWidget {
  const _SaasOverview({
    required this.data,
    required this.maxWidth,
    this.onOpenClients,
    this.onOpenBilling,
  });

  final _OverviewData data;
  final double maxWidth;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenBilling;

  @override
  Widget build(BuildContext context) {
    final tenants = data.kpiContaining('tenant');
    final pastDue = data.kpiContaining('atraso');
    final mrr = data.kpiContaining('mrr');
    final messages = data.kpiContaining('mensag');
    final twoCol = maxWidth >= 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: 'Operação SaaS',
          title: _saasTitle(data.overview.tenantName),
          subtitle: 'Indicadores da plataforma com os dados já calculados.',
        ),
        const SizedBox(height: 16),
        _KpiGrid(
          maxWidth: maxWidth,
          items: [
            _KpiSpec(
              label: 'Tenants ativos',
              value: tenants?.value ?? '—',
              hint: tenants?.helper,
              accent: AppColors.primary,
              onTap: onOpenClients,
            ),
            _KpiSpec(
              label: 'Planos em atraso',
              value: pastDue?.value ?? '—',
              hint: pastDue?.helper,
              accent: _isZero(pastDue?.value)
                  ? AppColors.textMuted
                  : AppColors.danger,
              onTap: onOpenBilling ?? onOpenClients,
            ),
            _KpiSpec(
              label: 'MRR estimado',
              value: mrr?.value ?? '—',
              hint: mrr?.helper,
              accent: AppColors.primarySoft,
              onTap: onOpenBilling,
            ),
            _KpiSpec(
              label: 'Mensagens no mês',
              value: messages?.value ?? '—',
              hint: messages?.helper,
              accent: AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (twoCol)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TopTenantsCard(items: data.overview.topTenants),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _RecentActivityCard(events: data.overview.recentEvents),
              ),
            ],
          )
        else ...[
          _TopTenantsCard(items: data.overview.topTenants),
          const SizedBox(height: 12),
          _RecentActivityCard(events: data.overview.recentEvents),
        ],
        if (onOpenClients != null) ...[
          const SizedBox(height: 16),
          _NextStepCard(
            title: 'Conta interna do sistema',
            body:
                'Selecione uma empresa em Clientes para configurar WhatsApp, automações e cobrança.',
            actionLabel: 'Gerenciar empresas',
            icon: Icons.apartment_rounded,
            onTap: onOpenClients!,
          ),
        ],
      ],
    );
  }

  static String _saasTitle(String? name) {
    final raw = (name ?? '').trim();
    if (raw.isEmpty || raw.toLowerCase().contains('operacao')) {
      return 'Operação SaaS';
    }
    return raw;
  }

  static bool _isZero(String? value) {
    final n = int.tryParse((value ?? '').replaceAll(RegExp(r'[^\d]'), ''));
    return n == null || n == 0;
  }
}

class _TenantOverview extends StatelessWidget {
  const _TenantOverview({
    required this.data,
    required this.maxWidth,
    required this.onOpenConversations,
    required this.onOpenAutomations,
    this.onOpenWhatsApp,
    this.onOpenTeam,
  });

  final _OverviewData data;
  final double maxWidth;
  final VoidCallback onOpenConversations;
  final VoidCallback onOpenAutomations;
  final VoidCallback? onOpenWhatsApp;
  final VoidCallback? onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final company = (data.overview.tenantName ?? '').trim().isEmpty
        ? 'Sua empresa'
        : data.overview.tenantName!.trim();
    final waiting = data.waitingConversations;
    final flows = data.kpiContaining('fluxo');
    final compact = maxWidth < 720;
    final needsWhatsApp = data.whatsappAccounts.isEmpty && onOpenWhatsApp != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          eyebrow: company,
          title: 'Como está o atendimento hoje?',
          subtitle: waiting == 0
              ? 'Nenhuma conversa aguardando resposta agora.'
              : '$waiting conversa${waiting == 1 ? '' : 's'} aguardando resposta.',
        ),
        const SizedBox(height: 16),
        _AttendanceHero(
          waiting: waiting,
          onOpen: onOpenConversations,
        ),
        const SizedBox(height: 12),
        _KpiGrid(
          maxWidth: maxWidth,
          items: [
            _KpiSpec(
              label: 'WhatsApp',
              value: _whatsAppValue(data),
              hint: _whatsAppHint(data),
              accent: data.whatsappAccounts.isEmpty
                  ? AppColors.warning
                  : AppColors.primary,
              onTap: onOpenWhatsApp,
            ),
            _KpiSpec(
              label: 'Mensagens no ciclo',
              value: _usageValue(data.subscription),
              hint: _usageHint(data.subscription),
              accent: AppColors.textMuted,
            ),
            _KpiSpec(
              label: 'Automações',
              value: flows?.value ?? '—',
              hint: flows?.helper ?? 'Fluxos no builder',
              accent: AppColors.accentSecondary,
              onTap: onOpenAutomations,
            ),
            _KpiSpec(
              label: 'Plano',
              value: operationPlanLabel(data.subscription?.plan ?? ''),
              hint: operationStatusLabel(data.subscription?.status ?? ''),
              accent: AppColors.textMuted,
            ),
          ],
        ),
        if (needsWhatsApp) ...[
          const SizedBox(height: 12),
          _NextStepCard(
            title: 'Conecte o WhatsApp da empresa',
            body:
                'O atendimento no painel começa quando a conta oficial estiver vinculada.',
            actionLabel: 'Abrir WhatsApp',
            icon: Icons.phonelink_setup_rounded,
            onTap: onOpenWhatsApp!,
          ),
        ],
        const SizedBox(height: 16),
        compact
            ? Column(
                children: [
                  _RecentConversationsCard(
                    conversations: data.conversations.take(8).toList(),
                    onOpen: onOpenConversations,
                  ),
                  if (data.overview.recentEvents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _RecentActivityCard(events: data.overview.recentEvents),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _RecentConversationsCard(
                      conversations: data.conversations.take(8).toList(),
                      onOpen: onOpenConversations,
                    ),
                  ),
                  if (data.overview.recentEvents.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _RecentActivityCard(
                        events: data.overview.recentEvents,
                      ),
                    ),
                  ],
                ],
              ),
        if (onOpenTeam != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenTeam,
              icon: const Icon(Icons.group_outlined, size: 16),
              label: const Text('Equipe'),
            ),
          ),
        ],
      ],
    );
  }

  static String _whatsAppValue(_OverviewData data) {
    if (data.whatsappAccounts.isEmpty) return 'Não configurado';
    final active = data.whatsappAccounts
        .where((a) => a.status.toLowerCase() == 'active')
        .length;
    if (active > 0) return '$active conectada${active > 1 ? 's' : ''}';
    return 'Pendente';
  }

  static String _whatsAppHint(_OverviewData data) {
    final wa = data.defaultWhatsApp;
    if (wa == null) return 'Vincule a conta oficial';
    if (wa.displayPhoneNumber.isNotEmpty) return wa.displayPhoneNumber;
    if (wa.displayName.isNotEmpty) return wa.displayName;
    return '${data.whatsappAccounts.length} conta(s)';
  }

  static String _usageValue(SubscriptionInfo? sub) {
    if (sub == null) return '—';
    if (sub.monthlyMessageLimit <= 0) return '${sub.usedMessages} msgs';
    return '${sub.usedMessages} de ${sub.monthlyMessageLimit}';
  }

  static String _usageHint(SubscriptionInfo? sub) {
    if (sub?.renewalDate != null) {
      return 'Renova em ${DateFormat('dd/MM/yyyy').format(sub!.renewalDate!)}';
    }
    return 'Uso no período';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: GoogleFonts.manrope(
            color: AppColors.primarySoft,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: GoogleFonts.manrope(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.label,
    required this.value,
    this.hint,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final Color accent;
  final VoidCallback? onTap;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items, required this.maxWidth});

  final List<_KpiSpec> items;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final columns = maxWidth >= 1000
        ? items.length.clamp(1, 4)
        : maxWidth >= 640
            ? 2
            : 1;
    return GridView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 92,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, i) => _KpiCard(spec: items[i]),
    );
  }
}

class _KpiCard extends StatefulWidget {
  const _KpiCard({required this.spec});

  final _KpiSpec spec;

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: spec.onTap,
        child: AnimatedContainer(
          duration: AppMotion.hoverOf(context),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lg,
            border: Border.all(
              color: _hover && spec.onTap != null
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                spec.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              if (spec.hint != null && spec.hint!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  spec.hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: spec.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceHero extends StatelessWidget {
  const _AttendanceHero({required this.waiting, required this.onOpen});

  final int waiting;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final idle = waiting == 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppRadius.xl,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.xl,
            border: Border.all(
              color: idle
                  ? AppColors.border
                  : AppColors.warning.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (idle ? AppColors.primary : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: AppRadius.md,
                ),
                child: Icon(
                  idle
                      ? Icons.check_circle_outline_rounded
                      : Icons.forum_outlined,
                  color: idle ? AppColors.primarySoft : AppColors.warning,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idle ? 'Fila em dia' : 'Fila de atendimento',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      idle
                          ? 'Nada pendente'
                          : '$waiting aguardando resposta',
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Abrir conversas',
                style: GoogleFonts.manrope(
                  color: AppColors.primarySoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String body;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 16),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentConversationsCard extends StatelessWidget {
  const _RecentConversationsCard({
    required this.conversations,
    required this.onOpen,
  });

  final List<Conversation> conversations;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      title: 'Conversas recentes',
      trailing: TextButton(
        onPressed: onOpen,
        child: const Text('Abrir fila'),
      ),
      child: conversations.isEmpty
          ? const _QuietEmpty(text: 'Nenhuma conversa ainda.')
          : Column(
              children: [
                for (final c in conversations)
                  InkWell(
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              c.phoneNumber,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Text(
                              c.lastMessage.isEmpty
                                  ? 'Sem mensagens'
                                  : c.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: Text(
                              c.formattedUpdatedAt,
                              textAlign: TextAlign.right,
                              style: GoogleFonts.manrope(
                                color: AppColors.textSoft,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TopTenantsCard extends StatelessWidget {
  const _TopTenantsCard({required this.items});

  final List<DashboardTopTenantModel> items;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      title: 'Empresas com maior uso',
      child: items.isEmpty
          ? const _QuietEmpty(
              text: 'Nenhum uso de mensagens no período atual.',
            )
          : Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.tenantName.isNotEmpty
                                    ? item.tenantName
                                    : item.tenantId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (item.plan.isNotEmpty)
                                    operationPlanLabel(item.plan),
                                  if (item.status.isNotEmpty)
                                    operationStatusLabel(item.status),
                                ].join(' · '),
                                style: GoogleFonts.manrope(
                                  color: AppColors.textSoft,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${item.usedMessages} msgs',
                          style: GoogleFonts.manrope(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.events});

  final List<DashboardRecentEventModel> events;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      title: 'Atividade recente',
      child: events.isEmpty
          ? const _QuietEmpty(text: 'Nenhum evento recente.')
          : Column(
              children: [
                for (final e in events.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.summary,
                                style: GoogleFonts.manrope(
                                  color: AppColors.text,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              if (e.createdAt != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('dd/MM HH:mm')
                                      .format(e.createdAt!.toLocal()),
                                  style: GoogleFonts.manrope(
                                    color: AppColors.textSoft,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _QuietEmpty extends StatelessWidget {
  const _QuietEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          color: AppColors.textMuted,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppPageInsets.of(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bone(width: 120, height: 12),
          const SizedBox(height: 10),
          _bone(width: 280, height: 22),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _bone(height: 88, radius: 10)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _bone(height: 180, radius: 12)),
              const SizedBox(width: 12),
              Expanded(child: _bone(height: 180, radius: 12)),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _bone({
    double? width,
    required double height,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduce(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.page,
      curve: AppMotion.pageCurve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
