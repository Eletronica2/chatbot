import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/conversation.dart';
import '../models/dashboard_overview.dart';
import '../models/subscription_info.dart';
import '../models/tenant_settings.dart';
import '../models/whatsapp_account.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../services/dashboard_service.dart';
import '../services/subscription_service.dart';
import '../services/tenant_service.dart';
import '../services/whatsapp_account_service.dart';
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
  late Future<_ActionCenterData> _future;
  final ScrollController _scrollCtrl = ScrollController();

  String get _tenantId => authService.tenantId ?? 'default';

  bool get _isSystemHomeContext =>
      authService.isSuperadmin &&
      _tenantId == (authService.homeTenantId ?? '');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<_ActionCenterData> _load() async {
    if (_isSystemHomeContext) {
      final overview = await dashboardService.fetchOverview();
      final conversations = await conversationService.fetchConversations();
      return _ActionCenterData(
        overview: overview,
        conversations: conversations,
        settings: TenantSettings(
          tenantId: _tenantId,
          tenantName: 'Conta do sistema',
          aiEnabled: false,
          flowEditingEnabled: false,
          debugMode: false,
          geminiModel: '',
          fallbackModels: const <String>[],
          availableModels: const <String>[],
        ),
        subscription: SubscriptionInfo(
          tenantId: _tenantId,
          plan: 'enterprise',
          status: 'active',
          renewalDate: null,
          monthlyMessageLimit: 0,
          active: true,
          usedMessages: 0,
          remainingMessages: 0,
        ),
        whatsappAccounts: const <WhatsAppAccountModel>[],
      );
    }

    final results = await Future.wait<dynamic>([
      dashboardService.fetchOverview(),
      conversationService.fetchConversations(),
      tenantService.fetchTenantSettings(_tenantId),
      subscriptionService.fetchSubscription(_tenantId),
      whatsAppAccountService.listAccounts(_tenantId),
    ]);

    return _ActionCenterData(
      overview: results[0] as DashboardOverviewModel,
      conversations: results[1] as List<Conversation>,
      settings: results[2] as TenantSettings,
      subscription: results[3] as SubscriptionInfo,
      whatsappAccounts: results[4] as List<WhatsAppAccountModel>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      child: FutureBuilder<_ActionCenterData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.dashboard_customize_rounded,
              title: 'Central de Ação indisponível',
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
              title: 'Sem dados',
              message: 'Nenhum dado retornado para esta empresa.',
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
                  controller: _scrollCtrl,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          data.overview.tenantName ?? 'Central de Ação',
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _StatusStrip(
                          data: data,
                          onOpenConversations: widget.onOpenConversations,
                          onOpenWhatsApp: widget.onOpenWhatsApp,
                          onOpenBilling: widget.onOpenBilling,
                        ),
                        if (data.overview.recentEvents.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _RecentActivityPanel(events: data.overview.recentEvents),
                        ],
                        if (authService.isSuperadmin &&
                            data.overview.topTenants.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _TopTenantsPanel(items: data.overview.topTenants),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        OperationHubPanel(
                          settings: data.settings,
                          subscription: data.subscription,
                          whatsappAccounts: data.whatsappAccounts,
                          onOpenBilling: widget.onOpenBilling,
                          onOpenClients: widget.onOpenClients,
                          onOpenWhatsApp: widget.onOpenWhatsApp,
                          onOpenConversations: widget.onOpenConversations,
                          onOpenAutomations: widget.onOpenAutomations,
                          onOpenTeam: widget.onOpenTeam,
                        ),
                      ],
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

class _ActionCenterData {
  const _ActionCenterData({
    required this.overview,
    required this.conversations,
    required this.settings,
    required this.subscription,
    required this.whatsappAccounts,
  });

  final DashboardOverviewModel overview;
  final List<Conversation> conversations;
  final TenantSettings settings;
  final SubscriptionInfo subscription;
  final List<WhatsAppAccountModel> whatsappAccounts;

  DashboardKpiModel? get _messagesKpi {
    for (final item in overview.kpis) {
      if (item.label.toLowerCase().contains('mensag')) return item;
    }
    return null;
  }

  int get waitingConversations =>
      conversations.where((c) => c.unreadCount > 0).length;

  String get messagesTodayValue {
    final direct = _messagesKpi;
    if (direct != null && direct.value.trim().isNotEmpty) return direct.value;
    final today = DateTime.now();
    final count = conversations.where((c) {
      final u = c.updatedAt.toLocal();
      return u.year == today.year &&
          u.month == today.month &&
          u.day == today.day;
    }).length;
    return '$count';
  }

  String get whatsAppStatus {
    if (whatsappAccounts.isEmpty) return 'Não configurado';
    final active = whatsappAccounts
        .where((a) => a.status.toLowerCase() == 'active')
        .length;
    if (active > 0) return '$active conectada${active > 1 ? 's' : ''}';
    return 'Pendente';
  }

  String get usageLabel {
    if (subscription.monthlyMessageLimit <= 0) {
      return '${subscription.usedMessages} msgs';
    }
    final pct = subscription.monthlyMessageLimit == 0
        ? 0
        : ((subscription.usedMessages / subscription.monthlyMessageLimit) * 100)
            .round();
    return '$pct% do limite';
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.data,
    required this.onOpenConversations,
    this.onOpenWhatsApp,
    this.onOpenBilling,
  });

  final _ActionCenterData data;
  final VoidCallback onOpenConversations;
  final VoidCallback? onOpenWhatsApp;
  final VoidCallback? onOpenBilling;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      PremiumStatusTile(
        expand: true,
        label: 'Fila de atendimento',
        value: '${data.waitingConversations}',
        hint: data.waitingConversations == 0
            ? 'Toque para abrir conversas'
            : 'Aguardando resposta — abrir fila',
        icon: Icons.mark_chat_unread_outlined,
        accent: data.waitingConversations > 0
            ? AppColors.warning
            : AppColors.textSoft,
        onTap: onOpenConversations,
      ),
      PremiumStatusTile(
        expand: true,
        label: 'Movimentação hoje',
        value: data.messagesTodayValue,
        hint: 'Ver conversas com atividade',
        icon: Icons.forum_outlined,
        accent: AppColors.info,
        onTap: onOpenConversations,
      ),
      PremiumStatusTile(
        expand: true,
        label: 'Consumo',
        value: data.usageLabel,
        hint: data.subscription.monthlyMessageLimit > 0
            ? '${data.subscription.remainingMessages} restantes'
            : 'Uso no período',
        icon: Icons.insights_outlined,
        accent: AppColors.accentBlue,
        onTap: onOpenBilling,
      ),
      PremiumStatusTile(
        expand: true,
        label: 'WhatsApp',
        value: data.whatsAppStatus,
        hint: data.whatsappAccounts.isEmpty
            ? 'Conectar número'
            : '${data.whatsappAccounts.length} conta(s)',
        icon: Icons.chat_outlined,
        accent: AppColors.success,
        onTap: onOpenWhatsApp ?? onOpenConversations,
      ),
      PremiumStatusTile(
        expand: true,
        label: 'Plano atual',
        value: operationPlanLabel(data.subscription.plan),
        hint: operationStatusLabel(data.subscription.status),
        icon: Icons.workspace_premium_outlined,
        accent: AppColors.primary,
        onTap: onOpenBilling,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 960) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: tiles
              .map(
                (tile) => SizedBox(
                  width: constraints.maxWidth >= 640
                      ? (constraints.maxWidth - AppSpacing.md) / 2
                      : constraints.maxWidth,
                  child: tile,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.events});

  final List<DashboardRecentEventModel> events;

  @override
  Widget build(BuildContext context) {
    return PremiumGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atividade recente',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          ...events.take(5).map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '• ${e.summary}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _TopTenantsPanel extends StatelessWidget {
  const _TopTenantsPanel({required this.items});

  final List<DashboardTopTenantModel> items;

  @override
  Widget build(BuildContext context) {
    return PremiumGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Empresas com maior uso',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.tenantName.isNotEmpty
                          ? item.tenantName
                          : item.tenantId,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${item.usedMessages} msgs',
                    style: const TextStyle(color: AppColors.textMuted),
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
