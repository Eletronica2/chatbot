import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import 'atenda_logo.dart';

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
    this.fillWidth = false,
    this.collapsed = false,
    this.onCollapsedChanged,
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
  final bool fillWidth;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsedChanged;

  List<Widget> _buildNavChildren({
    required List<AppSidebarItem> visibleItems,
    required String selectedId,
    required bool rail,
    required ValueChanged<String> onNavItemTap,
  }) {
    final children = <Widget>[];
    String? lastSection;
    var sawSection = false;

    for (final item in visibleItems) {
      final section = item.section?.trim();
      final hasSection = section != null && section.isNotEmpty;
      if (hasSection && section != lastSection) {
        sawSection = true;
        lastSection = section;
        if (!rail) {
          children.add(
            Padding(
              padding: EdgeInsets.fromLTRB(6, children.isEmpty ? 0 : 12, 6, 6),
              child: Text(
                section.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.55,
                ),
              ),
            ),
          );
        } else if (children.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: Divider(
                height: 1,
                color: AppColors.border.withValues(alpha: 0.7),
              ),
            ),
          );
        }
      } else if (!hasSection && !sawSection && children.isEmpty && !rail) {
        children.add(
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
        );
      }

      children.add(
        _SidebarNavItem(
          item: item,
          selected: item.id == selectedId,
          collapsed: rail,
          onTap: () => onNavItemTap(item.id),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) => item.visible).toList();
    final rail = !fillWidth && collapsed;
    final width = fillWidth
        ? double.infinity
        : (rail ? AppLayout.sidebarCollapsed : AppLayout.sidebarExpanded);

    return AnimatedContainer(
      duration: AppMotion.sidebarOf(context),
      curve: AppMotion.sidebarCurve,
      width: width,
      clipBehavior: Clip.hardEdge,
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
            collapsed: rail,
            onToggleCollapsed: fillWidth || onCollapsedChanged == null
                ? null
                : () => onCollapsedChanged!(!collapsed),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(rail ? 4 : 8, 0, rail ? 4 : 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._buildNavChildren(
                    visibleItems: visibleItems,
                    selectedId: selectedId,
                    rail: rail,
                    onNavItemTap: onNavItemTap,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(rail ? 6 : 10, 0, rail ? 6 : 10, 12),
            child: _UserFooter(
              email: userEmail,
              role: userRole,
              tenantLabel: activeTenantLabel,
              onLogout: onLogout,
              collapsed: rail,
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
    required this.collapsed,
    this.onToggleCollapsed,
  });

  final VoidCallback? onTap;
  final bool selected;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  State<_SidebarBrand> createState() => _SidebarBrandState();
}

class _SidebarBrandState extends State<_SidebarBrand> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mark = const AtendaLogo(height: 28, showWordmark: false);

    if (widget.collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          children: [
            Tooltip(
              message: 'Início',
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: AppRadius.md,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: mark),
                ),
              ),
            ),
            if (widget.onToggleCollapsed != null) ...[
              const SizedBox(height: 4),
              Semantics(
                button: true,
                label: 'Expandir menu',
                child: IconButton(
                  key: const ValueKey<String>('sidebar-expand'),
                  tooltip: 'Expandir menu',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                  onPressed: widget.onToggleCollapsed,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              duration: AppMotion.hoverOf(context),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                borderRadius: AppRadius.lg,
                // Neutro: não competir com item de navegação selecionado.
                border: Border.all(
                  color: _hovered ? AppColors.borderSubtle : Colors.transparent,
                ),
                color: _hovered
                    ? AppColors.surface.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: widget.onTap,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(child: mark),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: const AtendaLogo(height: 28, showWordmark: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onToggleCollapsed != null)
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: 'Recolher menu',
                child: IconButton(
                  key: const ValueKey<String>('sidebar-collapse'),
                  tooltip: 'Recolher menu',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onToggleCollapsed,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.textMuted,
                  ),
                ),
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
    required this.collapsed,
  });

  final AppSidebarItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final tip = widget.collapsed
        ? widget.item.label
        : (widget.item.helper?.trim().isNotEmpty == true
            ? widget.item.helper!.trim()
            : widget.item.label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.lg,
            child: AnimatedContainer(
              duration: AppMotion.hoverOf(context),
              height: 40,
              padding: EdgeInsets.symmetric(
                horizontal: widget.collapsed ? 0 : 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : (_hovering
                        ? AppColors.surfaceAlt.withValues(alpha: 0.55)
                        : Colors.transparent),
                borderRadius: AppRadius.md,
                border: Border.all(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
              ),
              child: widget.collapsed
                  ? Center(
                      child: Icon(
                        widget.item.icon,
                        size: 20,
                        color: selected
                            ? AppColors.primarySoft
                            : AppColors.textMuted,
                      ),
                    )
                  : Row(
                      children: [
                        Container(
                          width: 3,
                          height: 18,
                          margin: const EdgeInsets.only(right: 9),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Icon(
                          widget.item.icon,
                          size: 20,
                          color: selected
                              ? AppColors.primarySoft
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 13.5,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
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
    required this.collapsed,
    this.role,
    this.tenantLabel,
  });

  final String email;
  final String? role;
  final String? tenantLabel;
  final VoidCallback onLogout;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final seed = email.isNotEmpty ? email[0].toUpperCase() : 'A';
    final avatar = Container(
      width: collapsed ? 34 : 28,
      height: collapsed ? 34 : 28,
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        color: AppColors.surfaceSoft,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        seed,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: collapsed ? 13 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(message: email, child: avatar),
          const SizedBox(height: 4),
          IconButton(
            onPressed: onLogout,
            tooltip: 'Sair',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSoft,
              size: 18,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.55),
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  () {
                    final tenant = tenantLabel?.trim() ?? '';
                    if (tenant.isEmpty || tenant.toLowerCase() == 'default') {
                      return _humanizeRoleLabel(role);
                    }
                    return tenant;
                  }(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onLogout,
            tooltip: 'Sair',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSoft,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
