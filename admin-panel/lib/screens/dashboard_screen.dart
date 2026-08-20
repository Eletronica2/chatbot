import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/conversation_list.dart';
import '../widgets/premium_ui.dart';
import '../widgets/tenant_context_badge.dart';
import '../widgets/ui_audit_overlay.dart';
import '../widgets/ui_kit.dart';
import 'actions_screen.dart';
import 'backoffice_screen.dart';
import 'billing_hub_screen.dart';
import 'conversation_detail_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';
import 'template_dispatch_screen.dart';
import 'whatsapp_connection_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _navHome = 'home';
  static const String _navConversations = 'conversations';
  static const String _navAutomations = 'automations';
  static const String _navActions = 'actions';
  static const String _navClients = 'clients';
  static const String _navBilling = 'billing';
  static const String _navTemplates = 'templates';
  static const String _navWhatsApp = 'whatsapp';
  static const String _navTeam = 'team';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<Conversation>> _futureConversations;
  List<Conversation> _allConversations = <Conversation>[];
  List<Conversation> _filteredConversations = <Conversation>[];
  Conversation? _selectedConversation;
  String _selectedNav = _navHome;
  String _conversationFilter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _sidebarCollapsed = false;

  List<AppSidebarItem> get _sidebarItems {
    return <AppSidebarItem>[
      const AppSidebarItem(
        id: _navConversations,
        label: 'Conversas',
        icon: Icons.chat_bubble_rounded,
        helper: 'Atendimento, histórico e fila de resposta',
      ),
      const AppSidebarItem(
        id: _navAutomations,
        label: 'Automações',
        icon: Icons.auto_awesome_motion_rounded,
        helper: 'Monte etapas, respostas e simulações do chatbot',
      ),
      const AppSidebarItem(
        id: _navActions,
        label: 'Ações',
        icon: Icons.bolt_rounded,
        helper: 'Gerencie ações reutilizáveis: imagens, links, requisições HTTP',
      ),
      const AppSidebarItem(
        id: _navTemplates,
        label: 'Templates',
        icon: Icons.campaign_rounded,
        helper: 'Criar modelos Meta, ver status e disparar testes',
      ),
      AppSidebarItem(
        id: _navWhatsApp,
        label: 'WhatsApp',
        icon: Icons.phonelink_setup_rounded,
        helper: 'Conectar número, coexistência e contas da empresa',
        visible: !authService.isSuperadmin,
      ),
      AppSidebarItem(
        id: _navTeam,
        label: 'Equipe',
        icon: Icons.group_rounded,
        helper: 'Convide atendentes e gerentes da empresa',
        visible: !authService.isSuperadmin,
      ),
      AppSidebarItem(
        id: _navClients,
        label: 'Clientes',
        icon: Icons.business_rounded,
        helper: 'Empresas, usuários e números de WhatsApp',
        visible: authService.isSuperadmin,
      ),
      AppSidebarItem(
        id: _navBilling,
        label: 'Cobrança',
        icon: Icons.credit_card_rounded,
        helper: 'Planos, uso mensal e assinatura',
        visible: authService.isSuperadmin,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _futureConversations = _loadConversations();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Conversation>> _loadConversations() async {
    final data = await conversationService.fetchConversations();
    if (!mounted) return data;
    setState(() {
      _allConversations = data;
      _applyFilter(_searchCtrl.text);
    });
    return data;
  }

  void _refreshConversations() {
    final future = _loadConversations();
    setState(() {
      _futureConversations = future;
    });
  }

  void _applyFilter(String query) {
    final normalized = query.trim().toLowerCase();
    _filteredConversations = _allConversations.where((conversation) {
      final matchesQuery = normalized.isEmpty ||
          conversation.phoneNumber.toLowerCase().contains(normalized) ||
          conversation.lastMessage.toLowerCase().contains(normalized);
      return matchesQuery && _matchesConversationFilter(conversation);
    }).toList();
  }

  bool _matchesConversationFilter(Conversation conversation) {
    return switch (_conversationFilter) {
      'pending' => conversation.unreadCount > 0 ||
          conversation.humanHandoffPending,
      'ai' => conversation.aiEnabled,
      'human' => !conversation.aiEnabled ||
          conversation.humanHandoffPending,
      _ => true,
    };
  }

  void _setConversationFilter(String filter) {
    setState(() {
      _conversationFilter = filter;
      _applyFilter(_searchCtrl.text);
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _applyFilter(value));
  }

  void _selectNav(String navId) {
    setState(() {
      _selectedNav = navId;
      if (navId != _navConversations) {
        _selectedConversation = null;
        _sidebarCollapsed = false;
      }
    });
    if (navId == _navConversations) {
      _refreshConversations();
    }
  }

  Future<void> _openConversation(Conversation conversation) async {
    if (AppBreakpoints.useInboxSplit(context)) {
      setState(() {
        _selectedConversation = conversation;
        // Auto: conversa aberta → sidebar 68px (prioridade UX).
        _sidebarCollapsed = true;
      });
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(conversation: conversation),
      ),
    );
    _refreshConversations();
  }

  void _closeConversation() {
    setState(() {
      _selectedConversation = null;
      // Auto: sem conversa → sidebar 216px.
      _sidebarCollapsed = false;
    });
  }

  /// Manual expand/collapse é respeitado até o próximo select/deselect,
  /// quando o auto volta a ter prioridade.
  void _onSidebarCollapsedChanged(bool collapsed) {
    setState(() => _sidebarCollapsed = collapsed);
  }

  void _logout() {
    authService.logout();
    widget.onLogout();
  }

  Widget _buildSidebar({required bool fillWidth}) {
    final user = authService.currentUser;
    return AppSidebar(
      fillWidth: fillWidth,
      collapsed: fillWidth ? false : _sidebarCollapsed,
      onCollapsedChanged: fillWidth ? null : _onSidebarCollapsedChanged,
      items: _sidebarItems,
      selectedId: _selectedNav,
      onNavItemTap: (id) {
        if (fillWidth) {
          Navigator.of(context).maybePop();
        }
        _selectNav(id);
      },
      onHomeTap: () {
        if (fillWidth) {
          Navigator.of(context).maybePop();
        }
        _selectNav(_navHome);
      },
      homeSelected: _selectedNav == _navHome,
      userEmail: user?.email ?? 'admin@empresa.local',
      userRole: user?.role,
      activeTenantLabel: authService.tenantId,
      onLogout: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: authService,
      builder: (context, _) {
        final persistentSidebar = AppBreakpoints.usePersistentSidebar(context);

        final scaffold = Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: persistentSidebar
              ? null
              : Drawer(
                  backgroundColor: AppColors.sidebar,
                  width: ((MediaQuery.sizeOf(context).width * 0.86)
                          .clamp(260, 320))
                      .toDouble(),
                  child: _buildSidebar(fillWidth: true),
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (persistentSidebar) _buildSidebar(fillWidth: false),
                Expanded(
                  child: Container(
                    color: AppColors.background,
                    child: Column(
                      children: [
                        // Conversas wide: o chrome fica na inbox/chat — libera altura útil.
                        if (!(_selectedNav == _navConversations &&
                            persistentSidebar))
                          _ShellHeader(
                            title: _pageTitle,
                            subtitle: _pageSubtitle,
                            onRefresh: _selectedNav == _navConversations
                                ? _refreshConversations
                                : null,
                            onMenuTap: persistentSidebar
                                ? null
                                : () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                          ),
                        Expanded(
                          child: AppPageSwitcher(
                            // Troca de página por nav; refresh por tenant fica nos KeyedSubtree internos.
                            pageKey: _selectedNav,
                            child: _buildCurrentPage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        if (!kUiAudit) return scaffold;
        return Stack(
          children: [
            scaffold,
            const Positioned(
              left: 228,
              bottom: 10,
              child: UiAuditOverlay(),
            ),
          ],
        );
      },
    );
  }

  String get _pageTitle {
    switch (_selectedNav) {
      case _navConversations:
        return 'Conversas';
      case _navAutomations:
        return 'Automações';
      case _navActions:
        return 'Ações';
      case _navTemplates:
        return 'Templates WhatsApp';
      case _navWhatsApp:
        return 'WhatsApp';
      case _navTeam:
        return 'Equipe';
      case _navClients:
        return 'Clientes';
      case _navBilling:
        return 'Cobrança';
      default:
        return 'Início';
    }
  }

  String get _pageSubtitle {
    switch (_selectedNav) {
      case _navConversations:
        return 'Atenda com contexto, veja quem aguarda resposta e abra cada conversa como no WhatsApp Web.';
      case _navAutomations:
        return 'Organize a jornada do cliente em etapas, mensagens e respostas de um jeito simples de editar.';
      case _navActions:
        return 'Cadastre ações reutilizáveis — imagens, links, requisições HTTP e mais — para usar nos fluxos.';
      case _navTemplates:
        return 'Crie modelos oficiais da Meta, acompanhe PENDING/APPROVED e dispare testes.';
      case _navWhatsApp:
        return 'Conecte o WhatsApp Business da sua empresa e configure a coexistência.';
      case _navTeam:
        return 'Convide atendentes e gerentes para operar o painel da sua empresa.';
      case _navClients:
        return 'Acompanhe empresas, usuários, números de WhatsApp e o contexto ativo do SaaS.';
      case _navBilling:
        return 'Gerencie plano, uso, cobrança e saúde financeira da operação.';
      default:
        return 'Seu resumo operacional do dia.';
    }
  }

  Widget _buildCurrentPage() {
    switch (_selectedNav) {
      case _navConversations:
        return _buildConversationsPage();
      case _navAutomations:
        return KeyedSubtree(
          key: ValueKey<String>('automations-${authService.tenantId}'),
          child: const SettingsScreen(embedded: true),
        );
      case _navActions:
        return KeyedSubtree(
          key: ValueKey<String>('actions-${authService.tenantId}'),
          child: const ActionsScreen(),
        );
      case _navTemplates:
        return KeyedSubtree(
          key: ValueKey<String>('templates-${authService.tenantId}'),
          child: const TemplateDispatchScreen(),
        );
      case _navWhatsApp:
        return KeyedSubtree(
          key: ValueKey<String>('whatsapp-${authService.tenantId}'),
          child: const WhatsAppConnectionScreen(),
        );
      case _navTeam:
        return KeyedSubtree(
          key: ValueKey<String>('team-${authService.tenantId}'),
          child: const TeamScreen(),
        );
      case _navClients:
        return KeyedSubtree(
          key: const ValueKey<String>('clients'),
          child: BackofficeScreen(
            embedded: true,
            onLogout: _logout,
            onOpenTenantFlows: () => _selectNav(_navAutomations),
          ),
        );
      case _navBilling:
        return KeyedSubtree(
          key: ValueKey<String>('billing-${authService.tenantId}'),
          child: BillingHubScreen(
            onOpenBackoffice:
                authService.isSuperadmin ? () => _selectNav(_navClients) : null,
          ),
        );
      default:
        return KeyedSubtree(
          key: ValueKey<String>('home-${authService.tenantId}'),
          child: OverviewScreen(
            onOpenConversations: () => _selectNav(_navConversations),
            onOpenAutomations: () => _selectNav(_navAutomations),
            onOpenWhatsApp: authService.isSuperadmin
                ? () => _selectNav(_navClients)
                : () => _selectNav(_navWhatsApp),
            onOpenTeam: authService.isSuperadmin
                ? null
                : () => _selectNav(_navTeam),
            onOpenBilling:
                authService.isSuperadmin ? () => _selectNav(_navBilling) : null,
            onOpenClients:
                authService.isSuperadmin ? () => _selectNav(_navClients) : null,
          ),
        );
    }
  }

  Widget _buildConversationsPage() {
    final split = AppBreakpoints.useInboxSplit(context);
    final filters = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        PremiumFilterChip(
          label: 'Todos',
          selected: _conversationFilter == 'all',
          onTap: () => _setConversationFilter('all'),
        ),
        PremiumFilterChip(
          label: 'Pendentes',
          icon: Icons.priority_high_rounded,
          selected: _conversationFilter == 'pending',
          onTap: () => _setConversationFilter('pending'),
        ),
        PremiumFilterChip(
          label: 'IA ativa',
          icon: Icons.auto_awesome_rounded,
          selected: _conversationFilter == 'ai',
          onTap: () => _setConversationFilter('ai'),
        ),
        PremiumFilterChip(
          label: 'Humano',
          icon: Icons.support_agent_rounded,
          selected: _conversationFilter == 'human',
          onTap: () => _setConversationFilter('human'),
        ),
      ],
    );

    final listPane = ColoredBox(
      color: AppColors.sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Caixa de entrada',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refreshConversations,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar conversa...',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: filters,
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: FutureBuilder<List<Conversation>>(
              future: _futureConversations,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return AppEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Não foi possível carregar as conversas',
                    message: snapshot.error.toString(),
                    action: FilledButton.icon(
                      onPressed: _refreshConversations,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Tentar novamente'),
                    ),
                  );
                }
                if (_filteredConversations.isEmpty) {
                  return PremiumEmptyPanel(
                    icon: _searchCtrl.text.trim().isEmpty
                        ? Icons.mark_chat_unread_outlined
                        : Icons.search_off_rounded,
                    title: _searchCtrl.text.trim().isEmpty
                        ? 'Nenhuma conversa nesta fila'
                        : 'Nada encontrado',
                    description: _searchCtrl.text.trim().isEmpty
                        ? 'As conversas aparecem aqui assim que chegarem mensagens no WhatsApp.'
                        : 'Ajuste a busca ou escolha outro filtro para localizar a conversa.',
                    accent: AppColors.primary,
                  );
                }
                return ConversationList(
                  conversations: _filteredConversations,
                  selectedId: _selectedConversation?.id,
                  onSelectConversation: _openConversation,
                );
              },
            ),
          ),
        ],
      ),
    );

    if (!split) {
      return listPane;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: AppLayout.inboxWidth, child: listPane),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: _selectedConversation == null
              ? const _ConversationsEmptyState()
              : ConversationDetailScreen(
                  key: ValueKey<String>(_selectedConversation!.id),
                  conversation: _selectedConversation!,
                  embedded: true,
                  onClose: _closeConversation,
                ),
        ),
      ],
    );
  }
}

class _ConversationsEmptyState extends StatelessWidget {
  const _ConversationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 36,
                  color: AppColors.textSoft,
                ),
                SizedBox(height: 16),
                Text(
                  'Nenhuma conversa selecionada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Selecione uma conversa ao lado para visualizar as mensagens e continuar o atendimento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.45,
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

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onMenuTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRefresh;
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF06080F).withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final titleColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  color: AppColors.text,
                  fontSize: compact ? 18 : 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          );

          final menuButton = onMenuTap == null
              ? null
              : IconButton(
                  tooltip: 'Menu',
                  onPressed: onMenuTap,
                  icon: const Icon(Icons.menu_rounded, color: AppColors.text),
                );
          final companyChip =
              authService.isSuperadmin ? const TenantContextBadge() : null;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (menuButton != null) menuButton,
                    Expanded(child: titleColumn),
                  ],
                ),
                if (companyChip != null || onRefresh != null) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (companyChip != null) companyChip,
                      if (onRefresh != null)
                        PremiumGhostPill(
                          label: 'Atualizar',
                          icon: Icons.refresh_rounded,
                          onTap: onRefresh!,
                        ),
                    ],
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              if (menuButton != null) menuButton,
              Expanded(child: titleColumn),
              if (companyChip != null) ...[
                const SizedBox(width: 16),
                Flexible(child: companyChip),
              ],
              if (onRefresh != null) ...[
                const SizedBox(width: 10),
                PremiumGhostPill(
                  label: 'Atualizar',
                  icon: Icons.refresh_rounded,
                  onTap: onRefresh!,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
