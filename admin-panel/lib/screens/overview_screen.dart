import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conversation.dart';
import '../models/dashboard_overview.dart';
import '../models/tenant_settings.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../services/dashboard_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui_kit.dart';

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
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.onOpenConversations,
    required this.onOpenAutomations,
    required this.onOpenSettings,
    this.onOpenBilling,
    this.onOpenClients,
  });

  final VoidCallback onOpenConversations;
  final VoidCallback onOpenAutomations;
  final VoidCallback? onOpenBilling;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenClients;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<_ActionCenterData> _future;

  String get _tenantId => authService.tenantId ?? 'default';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ActionCenterData> _load() async {
    final results = await Future.wait<dynamic>([
      dashboardService.fetchOverview(),
      conversationService.fetchConversations(),
      tenantService.fetchTenantSettings(_tenantId),
    ]);

    return _ActionCenterData(
      overview: results[0] as DashboardOverviewModel,
      conversations: results[1] as List<Conversation>,
      settings: results[2] as TenantSettings,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: FutureBuilder<_ActionCenterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.dashboard_customize_rounded,
              title: 'Não foi possível abrir a Central de Ação',
              message: snapshot.error.toString(),
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
              icon: Icons.dashboard_customize_rounded,
              title: 'Central de Ação indisponível',
              message: 'Nenhum dado foi retornado para esta empresa.',
              action: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Atualizar'),
              ),
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
                  _ActionCenterHero(
                    data: data,
                    onOpenConversations: widget.onOpenConversations,
                    onOpenAutomations: widget.onOpenAutomations,
                    onOpenBilling: widget.onOpenBilling,
                    onOpenSettings: widget.onOpenSettings,
                    onOpenClients: widget.onOpenClients,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      AppMetricCard(
                        label: 'Conversas aguardando resposta',
                        value: '${data.waitingConversations}',
                        helper: data.waitingConversations == 0
                            ? 'Nenhuma conversa pendente agora'
                            : 'Clientes com mensagens sem leitura ou resposta recente',
                        icon: Icons.mark_chat_unread_rounded,
                        accent: data.waitingConversations == 0
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      AppMetricCard(
                        label: 'IA ativa agora',
                        value: data.settings.aiEnabled ? 'Sim' : 'Não',
                        helper: data.settings.aiEnabled
                            ? data.settings.geminiModel
                            : 'As respostas dependem das automações e do atendimento humano',
                        icon: Icons.smart_toy_rounded,
                        accent: data.settings.aiEnabled
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      AppMetricCard(
                        label: 'Mensagens hoje',
                        value: data.messagesTodayValue,
                        helper: data.messagesTodayHelper,
                        icon: Icons.forum_rounded,
                        accent: AppColors.info,
                      ),
                      AppMetricCard(
                        label: 'Status do sistema',
                        value: data.systemStatusTitle,
                        helper: data.systemStatusHelper,
                        icon: Icons.monitor_heart_rounded,
                        accent: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppPanelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionHeader(
                          title: 'Ações rápidas',
                          subtitle:
                              'Abra as áreas mais usadas sem precisar navegar por várias telas.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _QuickActionButton(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Abrir conversas',
                              helper: 'Entrar na fila de atendimento',
                              onTap: widget.onOpenConversations,
                            ),
                            _QuickActionButton(
                              icon: Icons.auto_awesome_motion_rounded,
                              label: 'Criar automação',
                              helper: 'Editar etapas e respostas',
                              onTap: widget.onOpenAutomations,
                            ),
                            _QuickActionButton(
                              icon: Icons.play_circle_outline_rounded,
                              label: 'Testar chatbot',
                              helper: 'Abrir o simulador das automações',
                              onTap: widget.onOpenAutomations,
                            ),
                            _QuickActionButton(
                              icon: Icons.tune_rounded,
                              label: 'Ajustar IA',
                              helper: 'Configurações da empresa em foco',
                              onTap: widget.onOpenSettings,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 1160;
                      final left = _RecentEventsPanel(events: data.overview.recentEvents);
                      final right = authService.isSuperadmin &&
                              data.overview.topTenants.isNotEmpty
                          ? _TopCompaniesPanel(items: data.overview.topTenants)
                          : _PlanUsagePanel(items: data.overview.planBreakdown);

                      if (compact) {
                        return Column(
                          children: [
                            left,
                            const SizedBox(height: AppSpacing.md),
                            right,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: AppSpacing.md),
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
}

class _ActionCenterData {
  const _ActionCenterData({
    required this.overview,
    required this.conversations,
    required this.settings,
  });

  final DashboardOverviewModel overview;
  final List<Conversation> conversations;
  final TenantSettings settings;

  DashboardKpiModel? get _messagesKpi {
    for (final item in overview.kpis) {
      if (item.label.toLowerCase().contains('mensag')) {
        return item;
      }
    }
    return null;
  }

  int get waitingConversations =>
      conversations.where((item) => item.unreadCount > 0).length;

  String get messagesTodayValue {
    final direct = _messagesKpi;
    if (direct != null && direct.value.trim().isNotEmpty) {
      return direct.value;
    }

    final today = DateTime.now();
    final count = conversations.where((conversation) {
      final updated = conversation.updatedAt.toLocal();
      return updated.year == today.year &&
          updated.month == today.month &&
          updated.day == today.day;
    }).length;
    return '$count';
  }

  String get messagesTodayHelper {
    final direct = _messagesKpi;
    if (direct != null && (direct.helper?.trim().isNotEmpty ?? false)) {
      return direct.helper!;
    }
    return 'Conversas com movimentação registrada hoje';
  }

  String get systemStatusTitle =>
      settings.aiEnabled ? 'Operando normalmente' : 'Em modo manual';

  String get systemStatusHelper => settings.aiEnabled
      ? 'IA ativa, automações carregadas e painel pronto para uso'
      : 'IA desligada; acompanhe respostas com automações e atendimento humano';
}

class _ActionCenterHero extends StatelessWidget {
  const _ActionCenterHero({
    required this.data,
    required this.onOpenConversations,
    required this.onOpenAutomations,
    required this.onOpenSettings,
    this.onOpenBilling,
    this.onOpenClients,
  });

  final _ActionCenterData data;
  final VoidCallback onOpenConversations;
  final VoidCallback onOpenAutomations;
  final VoidCallback? onOpenBilling;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenClients;

  @override
  Widget build(BuildContext context) {
    final scopeLabel = data.overview.scope == 'global'
        ? 'Visão geral da plataforma'
        : 'Visão da empresa em foco';

    return AppPanelCard(
      backgroundColor: AppColors.surfaceAlt,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppStatusChip(
                label: scopeLabel,
                icon: Icons.dashboard_customize_rounded,
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                foregroundColor: AppColors.primarySoft,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                data.overview.tenantName ?? 'Central de Ação',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                data.overview.scope == 'global'
                    ? 'Acompanhe métricas, uso, cobrança e o ritmo das empresas da sua plataforma em uma visão clara e executiva.'
                    : 'Abra o painel e descubra o que precisa de atenção agora: conversas, automações, IA e saúde da operação.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppStatusChip(
                    label: 'Empresa: ${authService.tenantId ?? 'default'}',
                    icon: Icons.apartment_rounded,
                    backgroundColor: AppColors.surfaceSoft,
                  ),
                  AppStatusChip(
                    label: data.settings.aiEnabled ? 'IA ligada' : 'IA desligada',
                    icon: data.settings.aiEnabled
                        ? Icons.auto_awesome_rounded
                        : Icons.pause_circle_outline_rounded,
                    backgroundColor: data.settings.aiEnabled
                        ? AppColors.success.withValues(alpha: 0.14)
                        : AppColors.warning.withValues(alpha: 0.14),
                    foregroundColor: data.settings.aiEnabled
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ],
              ),
            ],
          );

          final actions = Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onOpenConversations,
                icon: const Icon(Icons.chat_bubble_rounded),
                label: const Text('Abrir conversas'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenAutomations,
                icon: const Icon(Icons.auto_awesome_motion_rounded),
                label: const Text('Abrir automações'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Configurações'),
              ),
              if (onOpenBilling != null)
                OutlinedButton.icon(
                  onPressed: onOpenBilling,
                  icon: const Icon(Icons.credit_card_rounded),
                  label: const Text('Ver cobrança'),
                ),
              if (onOpenClients != null)
                OutlinedButton.icon(
                  onPressed: onOpenClients,
                  icon: const Icon(Icons.business_rounded),
                  label: const Text('Abrir clientes'),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                intro,
                const SizedBox(height: AppSpacing.lg),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intro),
              const SizedBox(width: AppSpacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: actions,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: AppRadius.lg,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 240,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceSoft : AppColors.surfaceAlt,
            borderRadius: AppRadius.lg,
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.32)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: AppRadius.md,
                ),
                child: Icon(widget.icon, color: AppColors.primarySoft, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.helper,
                      style: const TextStyle(
                        color: AppColors.textSoft,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentEventsPanel extends StatelessWidget {
  const _RecentEventsPanel({
    required this.events,
  });

  final List<DashboardRecentEventModel> events;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'O que aconteceu recentemente',
            subtitle:
                'Mudanças administrativas e eventos importantes da operação aparecem aqui.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (events.isEmpty)
            const AppEmptyState(
              icon: Icons.event_note_rounded,
              title: 'Nenhum evento recente',
              message: 'As próximas alterações importantes aparecerão aqui.',
            )
          else
            Column(
              children: events
                  .take(6)
                  .map(
                    (event) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: AppRadius.md,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.14),
                              borderRadius: AppRadius.md,
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: AppColors.info,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.summary,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${event.tenantId} • ${event.actorEmail ?? 'Sistema'}',
                                  style: const TextStyle(
                                    color: AppColors.textSoft,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            event.createdAt == null
                                ? '--'
                                : DateFormat('dd/MM HH:mm')
                                    .format(event.createdAt!.toLocal()),
                            style: const TextStyle(
                              color: AppColors.textSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _PlanUsagePanel extends StatelessWidget {
  const _PlanUsagePanel({
    required this.items,
  });

  final List<DashboardPlanBreakdownModel> items;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Uso por plano',
            subtitle:
                'Distribuição das empresas por plano e potencial de receita estimada.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (items.isEmpty)
            const AppEmptyState(
              icon: Icons.stacked_bar_chart_rounded,
              title: 'Sem dados de plano ainda',
              message: 'Quando houver dados de uso e cobrança, eles aparecerão aqui.',
            )
          else
            Column(
              children: items
                  .map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: AppRadius.md,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _overviewPlanLabel(item.plan),
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${item.tenants} empresas',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _TopCompaniesPanel extends StatelessWidget {
  const _TopCompaniesPanel({
    required this.items,
  });

  final List<DashboardTopTenantModel> items;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Empresas com maior uso',
            subtitle:
                'Veja rapidamente quais empresas estão mais ativas agora.',
          ),
          const SizedBox(height: AppSpacing.lg),
          if (items.isEmpty)
            const AppEmptyState(
              icon: Icons.business_center_rounded,
              title: 'Nenhuma empresa em destaque',
              message: 'As empresas com maior atividade aparecerão aqui.',
            )
          else
            Column(
              children: items
                  .take(6)
                  .map(
                    (item) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
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
                                  item.tenantName,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              AppStatusChip(
                                label: _overviewStatusLabel(item.status),
                                backgroundColor: AppColors.surfaceSoft,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${item.usedMessages} de ${item.monthlyMessageLimit} mensagens',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
