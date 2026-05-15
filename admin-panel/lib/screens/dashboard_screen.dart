import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/conversation_list.dart';
import '../widgets/ui_kit.dart';
import 'actions_screen.dart';
import 'backoffice_screen.dart';
import 'billing_hub_screen.dart';
import 'conversation_detail_screen.dart';
import 'overview_screen.dart';
import 'settings_hub_screen.dart';
import 'settings_screen.dart';

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
  static const String _navSettings = 'settings';

  late Future<List<Conversation>> _futureConversations;
  List<Conversation> _allConversations = <Conversation>[];
  List<Conversation> _filteredConversations = <Conversation>[];
  String _selectedNav = _navHome;
  final TextEditingController _searchCtrl = TextEditingController();

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
      const AppSidebarItem(
        id: _navSettings,
        label: 'Configurações',
        icon: Icons.tune_rounded,
        helper: 'IA, contexto da empresa e ajustes gerais',
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
    if (normalized.isEmpty) {
      _filteredConversations = List<Conversation>.from(_allConversations);
      return;
    }
    _filteredConversations = _allConversations.where((conversation) {
      return conversation.phoneNumber.toLowerCase().contains(normalized) ||
          conversation.lastMessage.toLowerCase().contains(normalized);
    }).toList();
  }

  void _onSearchChanged(String value) {
    setState(() => _applyFilter(value));
  }

  void _selectNav(String navId) {
    setState(() {
      _selectedNav = navId;
    });
    if (navId == _navConversations) {
      _refreshConversations();
    }
  }

  Future<void> _openConversation(Conversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(conversation: conversation),
      ),
    );
    _refreshConversations();
  }

  void _logout() {
    authService.logout();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          AppSidebar(
            items: _sidebarItems,
            selectedId: _selectedNav,
            onNavItemTap: _selectNav,
            onHomeTap: () => _selectNav(_navHome),
            homeSelected: _selectedNav == _navHome,
            userEmail: user?.email ?? 'admin@empresa.local',
            userRole: user?.role,
            activeTenantLabel: authService.tenantId,
            onLogout: _logout,
          ),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Column(
                children: [
                  _ShellHeader(
                    title: _pageTitle,
                    subtitle: _pageSubtitle,
                    companyLabel: authService.tenantId ?? '-',
                    onRefresh: _selectedNav == _navConversations
                        ? _refreshConversations
                        : null,
                  ),
                  Expanded(child: _buildCurrentPage()),
                ],
              ),
            ),
          ),
        ],
      ),
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
      case _navClients:
        return 'Clientes';
      case _navBilling:
        return 'Cobrança';
      case _navSettings:
        return 'Configurações';
      default:
        return 'Central de Ação';
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
      case _navClients:
        return 'Acompanhe empresas, usuários, números de WhatsApp e o contexto ativo do SaaS.';
      case _navBilling:
        return 'Gerencie plano, uso, cobrança e saúde financeira da operação.';
      case _navSettings:
        return 'Ajuste IA, modo de operação e atalhos importantes da empresa em foco.';
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
      case _navClients:
        return KeyedSubtree(
          key: ValueKey<String>('clients-${authService.tenantId}'),
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
      case _navSettings:
        return KeyedSubtree(
          key: ValueKey<String>('settings-${authService.tenantId}'),
          child: SettingsHubScreen(
            onOpenAutomations: () => _selectNav(_navAutomations),
            onOpenBilling:
                authService.isSuperadmin ? () => _selectNav(_navBilling) : null,
            onOpenClients:
                authService.isSuperadmin ? () => _selectNav(_navClients) : null,
          ),
        );
      default:
        return KeyedSubtree(
          key: ValueKey<String>('home-${authService.tenantId}'),
          child: OverviewScreen(
            onOpenConversations: () => _selectNav(_navConversations),
            onOpenAutomations: () => _selectNav(_navAutomations),
            onOpenBilling:
                authService.isSuperadmin ? () => _selectNav(_navBilling) : null,
            onOpenSettings: () => _selectNav(_navSettings),
            onOpenClients:
                authService.isSuperadmin ? () => _selectNav(_navClients) : null,
          ),
        );
    }
  }

  Widget _buildConversationsPage() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          AppPanelCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                final searchField = SizedBox(
                  width: compact ? double.infinity : 360,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por número, nome ou última mensagem...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                );

                final intro = const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inbox estilo WhatsApp',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Veja quem está aguardando, abra a conversa e responda com mais contexto em menos cliques.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      intro,
                      const SizedBox(height: 16),
                      searchField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: intro),
                    const SizedBox(width: 16),
                    searchField,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AppPanelCard(
              padding: EdgeInsets.zero,
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
                    return AppEmptyState(
                      icon: _searchCtrl.text.trim().isEmpty
                          ? Icons.mark_chat_unread_outlined
                          : Icons.search_off_rounded,
                      title: _searchCtrl.text.trim().isEmpty
                          ? 'Nenhuma conversa ainda'
                          : 'Nada encontrado',
                      message: _searchCtrl.text.trim().isEmpty
                          ? 'As conversas vão aparecer aqui assim que chegarem mensagens no WhatsApp.'
                          : 'Tente mudar o termo pesquisado para encontrar a conversa desejada.',
                    );
                  }
                  return ConversationList(
                    conversations: _filteredConversations,
                    onSelectConversation: _openConversation,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
    required this.companyLabel,
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final String companyLabel;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final companyChip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Empresa em foco: $companyLabel',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          final refreshButton = onRefresh == null
              ? const SizedBox.shrink()
              : FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Atualizar'),
                );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionHeader(title: title, subtitle: subtitle),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    companyChip,
                    if (onRefresh != null) refreshButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: AppSectionHeader(title: title, subtitle: subtitle),
              ),
              const SizedBox(width: 16),
              companyChip,
              if (onRefresh != null) ...[
                const SizedBox(width: 10),
                refreshButton,
              ],
            ],
          );
        },
      ),
    );
  }
}
