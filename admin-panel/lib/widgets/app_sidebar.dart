import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      width: 248,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(
          right: BorderSide(color: Color(0xFF242938)),
        ),
      ),
      child: Column(
        children: [
          _SidebarBrand(
            selected: homeSelected,
            onTap: onHomeTap,
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
              borderRadius: AppRadius.lg,
              border: Border.all(
                color: widget.selected
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
              color: widget.selected || _hovered
                  ? AppColors.surface.withValues(alpha: 0.85)
                  : Colors.transparent,
              boxShadow: widget.selected ? AppShadows.navActive : null,
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
                        gradient: AppGradients.brandIcon,
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
                          Text(
                            'Central de Ação',
                            style: GoogleFonts.inter(
                              color: AppColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            interactive ? 'Painel principal' : 'Operação',
                            style: GoogleFonts.inter(
                              color: AppColors.textSoft,
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
              ],
            ),
          ),
        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : (_hovering
                      ? AppColors.surfaceAlt.withValues(alpha: 0.55)
                      : Colors.transparent),
              borderRadius: AppRadius.md,
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
                top: BorderSide(
                  color: selected
                      ? const Color(0xFF242938)
                      : Colors.transparent,
                ),
                right: BorderSide(
                  color: selected
                      ? const Color(0xFF242938)
                      : Colors.transparent,
                ),
                bottom: BorderSide(
                  color: selected
                      ? const Color(0xFF242938)
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.label,
                        style: TextStyle(
                          color: selected ? AppColors.text : AppColors.text,
                          fontSize: 13.5,
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
