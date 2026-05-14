import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

String _humanizeRoleLabel(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  if (normalized.contains('system')) return 'Administrador do sistema';
  if (normalized.contains('super')) return 'Superadministrador';
  if (normalized.contains('owner')) return 'Admin da empresa';
  if (normalized.contains('manager')) return 'Gerente';
  if (normalized.contains('agent')) return 'Atendente';
  return 'Usuário';
}

class AppSidebarItem {
  const AppSidebarItem({
    required this.id,
    required this.label,
    required this.icon,
    this.section,
    this.helper,
    this.visible = true,
  });

  final String id;
  final String label;
  final IconData icon;
  final String? section;
  final String? helper;
  final bool visible;
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onNavItemTap,
    required this.userEmail,
    required this.onLogout,
    this.userRole,
    this.activeTenantLabel,
    this.onHomeTap,
    this.homeSelected = false,
  });

  final List<AppSidebarItem> items;
  final String selectedId;
  final ValueChanged<String> onNavItemTap;
  final String userEmail;
  final VoidCallback onLogout;
  final String? userRole;
  final String? activeTenantLabel;
  final VoidCallback? onHomeTap;
  final bool homeSelected;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) => item.visible).toList();

    return Container(
      width: 304,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _SidebarBrand(
            selected: homeSelected,
            onTap: onHomeTap,
          ),
          if (activeTenantLabel != null && activeTenantLabel!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _CompanyFocusCard(
                label: activeTenantLabel!,
                userRole: userRole,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                    child: Text(
                      'Navegação principal',
                      style: TextStyle(
                        color: AppColors.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final item in visibleItems)
                    _SidebarNavItem(
                      item: item,
                      selected: item.id == selectedId,
                      onTap: () => onNavItemTap(item.id),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _UserFooter(
              email: userEmail,
              role: userRole,
              onLogout: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatefulWidget {
  const _SidebarBrand({
    this.onTap,
    required this.selected,
  });

  final VoidCallback? onTap;
  final bool selected;

  @override
  State<_SidebarBrand> createState() => _SidebarBrandState();
}

class _SidebarBrandState extends State<_SidebarBrand> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: AppRadius.xl,
              border: Border.all(
                color: widget.selected
                    ? AppColors.primary.withValues(alpha: 0.65)
                    : AppColors.border,
              ),
              gradient: LinearGradient(
                colors: [
                  widget.selected || _hovered
                      ? const Color(0xFF171F34)
                      : AppColors.surface,
                  const Color(0xFF0F1627),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: widget.selected || _hovered
                  ? AppShadows.hover
                  : AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        borderRadius: AppRadius.md,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryStrong,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Central de Ação',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            interactive
                                ? 'Clique para voltar ao painel principal'
                                : 'Seu painel de operação do chatbot',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (interactive)
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: widget.selected
                            ? AppColors.primarySoft
                            : AppColors.textSoft,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: AppColors.primarySoft),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Converse, automatize, acompanhe cobrança e gerencie empresas em um só lugar.',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
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

class _CompanyFocusCard extends StatelessWidget {
  const _CompanyFocusCard({
    required this.label,
    this.userRole,
  });

  final String label;
  final String? userRole;

  @override
  Widget build(BuildContext context) {
    final normalizedRole = (userRole ?? '').trim().toLowerCase();
    final contextLabel = normalizedRole.contains('system')
        ? 'Sistema'
        : normalizedRole.contains('super')
            ? 'Administrador SaaS'
            : 'Empresa';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  contextLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.radar_rounded, color: AppColors.success, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Empresa em foco',
            style: TextStyle(
              color: AppColors.textSoft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppSidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: AppRadius.lg,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.surface
                  : (_hovering
                      ? AppColors.surfaceAlt.withValues(alpha: 0.92)
                      : Colors.transparent),
              borderRadius: AppRadius.lg,
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.30)
                    : Colors.transparent,
              ),
              boxShadow: selected || _hovering ? AppShadows.hover : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.surfaceSoft : AppColors.surfaceAlt,
                    borderRadius: AppRadius.md,
                  ),
                  child: Icon(
                    widget.item.icon,
                    size: 20,
                    color: selected ? AppColors.primarySoft : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.label,
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.text,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (widget.item.helper != null &&
                          widget.item.helper!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.item.helper!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSoft,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.north_east_rounded : Icons.chevron_right_rounded,
                  color: selected ? AppColors.primarySoft : AppColors.textSoft,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.email,
    required this.onLogout,
    this.role,
  });

  final String email;
  final String? role;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final seed = email.isNotEmpty ? email[0].toUpperCase() : 'A';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              borderRadius: AppRadius.md,
              gradient: LinearGradient(
                colors: [AppColors.primaryStrong, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              seed,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _humanizeRoleLabel(role),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onLogout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout_rounded, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
