import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/conversation_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/conversation_list.dart';
import 'conversation_detail_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Conversation>> _future;
  List<Conversation> _all = [];
  List<Conversation> _filtered = [];
  int _navIndex = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Conversation>> _load() async {
    final data = await conversationService.fetchConversations();
    setState(() {
      _all = data;
      _applyFilter(_searchCtrl.text);
    });
    return data;
  }

  void _applyFilter(String q) {
    if (q.isEmpty) {
      _filtered = List.of(_all);
    } else {
      final lower = q.toLowerCase();
      _filtered = _all
          .where((c) =>
              c.phoneNumber.toLowerCase().contains(lower) ||
              c.lastMessage.toLowerCase().contains(lower))
          .toList();
    }
  }

  void _onSearch(String q) {
    setState(() => _applyFilter(q));
  }

  void _refresh() {
    _searchCtrl.clear();
    setState(() => _future = _load());
  }

  void _openConversation(Conversation c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(conversation: c),
      ),
    );
  }

  void _onNavTap(int i) {
    if (i == 1) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    } else {
      setState(() => _navIndex = i);
    }
  }

  void _logout() {
    authService.logout();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Row(
        children: [
          AppSidebar(
            selectedIndex: _navIndex,
            onNavItemTap: _onNavTap,
            userEmail: user?.email ?? 'admin',
            onLogout: _logout,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  searchCtrl: _searchCtrl,
                  onSearch: _onSearch,
                  onRefresh: _refresh,
                ),
                Expanded(
                  child: FutureBuilder<List<Conversation>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const _LoadingState();
                      }
                      if (snap.hasError) {
                        return _ErrorState(
                          error: snap.error.toString(),
                          onRetry: _refresh,
                        );
                      }
                      if (_filtered.isEmpty) {
                        return _EmptyState(searched: _searchCtrl.text.isNotEmpty);
                      }
                      return ConversationList(
                        conversations: _filtered,
                        onSelectConversation: _openConversation,
                      );
                    },
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

class _Header extends StatelessWidget {
  const _Header({
    required this.searchCtrl,
    required this.onSearch,
    required this.onRefresh,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Conversas',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE2E8F0),
                      ),
                ),
                Text(
                  'Monitore e responda em tempo real',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 260,
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearch,
              style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
              decoration: InputDecoration(
                hintText: 'Buscar por número ou mensagem...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _IconBtn(
            icon: Icons.refresh_rounded,
            tooltip: 'Atualizar',
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF334155)),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF1E293B),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 14),
          Text(
            'Não foi possível carregar',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searched});
  final bool searched;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searched ? Icons.search_off_rounded : Icons.chat_bubble_outline_rounded,
              size: 36,
              color: const Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searched ? 'Nenhum resultado' : 'Sem conversas ainda',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            searched
                ? 'Tente ajustar os termos da busca'
                : 'As conversas aparecerão aqui quando chegarem',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}