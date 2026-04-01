import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/conversation_list.dart';
import 'backoffice_screen.dart';
import 'billing_hub_screen.dart';
import 'conversation_detail_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';

const _kBg = Color(0xFF081120);
const _kShellSurface = Color(0xFF0B1120);
const _kTopbar = Color(0xFF10192A);
const _kPanel = Color(0xFF111827);
const _kBorder = Color(0xFF223041);
const _kText = Color(0xFFE2E8F0);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kAccent = Color(0xFF7C8CFF);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _navOverview = 'overview';
  static const String _navConversations = 'conversations';
  static const String _navFlows = 'flows';
  static const String _navBilling = 'billing';
  static const String _navBackoffice = 'backoffice';

  late Future<List<Conversation>> _futureConversations;
  List<Conversation> _allConversations = <Conversation>[];
  List<Conversation> _filteredConversations = <Conversation>[];
  String _selectedNav = _navOverview;
  final TextEditingController _searchCtrl = TextEditingController();

  List<AppSidebarItem> get _sidebarItems {
    return <AppSidebarItem>[
      const AppSidebarItem(
        id: _navOverview,
        label: 'Visão geral',
        icon: Icons.space_dashboard_rounded,
        section: 'Operação',
        helper: 'Métricas, status e atalhos rápidos',
      ),
      const AppSidebarItem(
        id: _navConversations,
        label: 'Conversas',
        icon: Icons.chat_bubble_outline_rounded,
        section: 'Operação',
        helper: 'Atendimento e histórico em tempo real',
      ),
      const AppSidebarItem(
        id: _navFlows,
        label: 'Fluxos',
        icon: Icons.account_tree_outlined,
        section: 'Operação',
        helper: 'Editor visual do chatbot',
      ),
      const AppSidebarItem(
        id: _navBilling,
        label: 'Cobrança',
        icon: Icons.credit_card_rounded,
        section: 'Operação',
        helper: 'Planos, pagamentos e assinatura',
      ),
      AppSidebarItem(
        id: _navBackoffice,
        label: 'Administração SaaS',
        icon: Icons.apartment_rounded,
        section: 'Operação SaaS',
        helper: 'Clientes, usuários e contas WhatsApp',
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
    if (normalized.isEmpty) {
      _filteredConversations = List<Conversation>.from(_allConversations);
      return;
    }
    _filteredConversations = _allConversations.where((conversation) {
      return conversation.phoneNumber.toLowerCase().contains(normalized) || conversation.lastMessage.toLowerCase().contains(normalized);
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
      backgroundColor: _kBg,
      body: Row(
        children: [
          AppSidebar(
            items: _sidebarItems,
            selectedId: _selectedNav,
            onNavItemTap: _selectNav,
            userEmail: user?.email ?? 'admin',
            userRole: user?.role,
            activeTenantLabel: authService.tenantId,
            onLogout: _logout,
          ),
          Expanded(
            child: Container(
              color: _kShellSurface,
              child: Column(
                children: [
                  if (_showShellHeader)
                    _ShellHeader(
                      title: _pageTitle,
                      subtitle: _pageSubtitle,
                      tenantLabel: authService.tenantId ?? '-',
                      onRefresh: _selectedNav == _navConversations ? _refreshConversations : null,
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

  bool get _showShellHeader => _selectedNav == _navOverview || _selectedNav == _navConversations || _selectedNav == _navBilling;

  String get _pageTitle {
    switch (_selectedNav) {
      case _navConversations:
        return 'Central de conversas';
      case _navFlows:
        return 'Editor de fluxos';
      case _navBilling:
        return 'Cobrança e assinatura';
      case _navBackoffice:
        return 'Administração SaaS';
      default:
        return authService.isSuperadmin && authService.tenantId == (authService.homeTenantId ?? '')
            ? 'Operação global da plataforma'
            : 'Visão geral do chatbot';
    }
  }

  String get _pageSubtitle {
    switch (_selectedNav) {
      case _navConversations:
        return 'Acompanhe mensagens, histórico e o estado atual do atendimento.';
      case _navFlows:
        return 'Edite automações, simulações e o comportamento do chatbot.';
      case _navBilling:
        return 'Gerencie plano, pagamento, portal de cobrança e bloqueio por inadimplência.';
      case _navBackoffice:
        return 'Administre clientes, usuários, contas WhatsApp e contexto do SaaS.';
      default:
        return 'Métricas, eventos recentes e atalhos das principais áreas do produto.';
    }
  }

  Widget _buildCurrentPage() {
    switch (_selectedNav) {
      case _navConversations:
        return _buildConversationsPage();
      case _navFlows:
        return KeyedSubtree(
          key: ValueKey<String>('flows-${authService.tenantId}'),
          child: const SettingsScreen(embedded: true),
        );
      case _navBilling:
        return KeyedSubtree(
          key: ValueKey<String>('billing-${authService.tenantId}'),
          child: BillingHubScreen(
            onOpenBackoffice: authService.isSuperadmin ? () => _selectNav(_navBackoffice) : null,
          ),
        );
      case _navBackoffice:
        return KeyedSubtree(
          key: ValueKey<String>('backoffice-${authService.tenantId}'),
          child: BackofficeScreen(
            embedded: true,
            onLogout: _logout,
            onOpenTenantFlows: () => _selectNav(_navFlows),
          ),
        );
      default:
        return KeyedSubtree(
          key: ValueKey<String>('overview-${authService.tenantId}'),
          child: OverviewScreen(
            onOpenConversations: () => _selectNav(_navConversations),
            onOpenFlows: () => _selectNav(_navFlows),
            onOpenBilling: () => _selectNav(_navBilling),
            onOpenBackoffice: authService.isSuperadmin ? () => _selectNav(_navBackoffice) : null,
          ),
        );
    }
  }

  Widget _buildConversationsPage() {
    return Container(
      color: _kShellSurface,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _kPanel,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _kBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x16000000),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 880;
                final searchField = SizedBox(
                  width: compact ? double.infinity : 320,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 13, color: _kText),
                    decoration: InputDecoration(
                        hintText: 'Buscar por número ou mensagem...',
                      hintStyle: const TextStyle(fontSize: 13, color: _kSubtle),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: _kMuted,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _kAccent, width: 2),
                      ),
                    ),
                  ),
                );

                final intro = const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inbox operacional',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Acompanhe atendimento, status da IA e mensagens mais recentes.',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 12,
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: _kPanel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _kBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 24,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: FutureBuilder<List<Conversation>>(
                  future: _futureConversations,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _SimpleState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Não foi possível carregar as conversas',
                        message: snapshot.error.toString(),
                        actionLabel: 'Tentar novamente',
                        onTap: _refreshConversations,
                      );
                    }
                    if (_filteredConversations.isEmpty) {
                      return _SimpleState(
                        icon: _searchCtrl.text.trim().isEmpty ? Icons.chat_bubble_outline_rounded : Icons.search_off_rounded,
                        title: _searchCtrl.text.trim().isEmpty ? 'Sem conversas por enquanto' : 'Nenhum resultado encontrado',
                        message:
                            _searchCtrl.text.trim().isEmpty ? 'As conversas aparecerão aqui quando chegarem mensagens no WhatsApp.' : 'Ajuste o termo pesquisado para encontrar a conversa desejada.',
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
    required this.tenantLabel,
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final String tenantLabel;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: const BoxDecoration(
        color: _kTopbar,
        border: Border(bottom: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final contextBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF182235),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Text(
              'Cliente em foco: $tenantLabel',
              style: const TextStyle(
                color: _kText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          final action = onRefresh == null
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
                Text(
                  title,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    contextBadge,
                    if (onRefresh != null) action,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              contextBadge,
              if (onRefresh != null) ...[
                const SizedBox(width: 10),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SimpleState extends StatelessWidget {
  const _SimpleState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: _kMuted),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
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
              if (actionLabel != null && onTap != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
