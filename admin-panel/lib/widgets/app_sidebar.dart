import 'package:flutter/material.dart';

const _kBg = Color(0xFF081120);
const _kSurface = Color(0xFF111827);
const _kSurfaceSoft = Color(0xFF172033);
const _kHover = Color(0xFF1E293B);
const _kActive = Color(0xFF7C8CFF);
const _kBorder = Color(0xFF243041);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kText = Color(0xFFE2E8F0);
const _kSuccess = Color(0xFF10B981);

String _humanizeRoleLabel(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  if (normalized.contains('system')) return 'Administrador do sistema';
  if (normalized.contains('super')) return 'Superadministrador';
  if (normalized.contains('owner')) return 'Proprietário';
  if (normalized.contains('manager')) return 'Gerente';
  if (normalized.isEmpty) return 'Usuário';
  return 'Usuário';
}

class AppSidebarItem {
  const AppSidebarItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.section,
    this.helper,
    this.visible = true,
  });

  final String id;
  final String label;
  final IconData icon;
  final String section;
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
  });

  final List<AppSidebarItem> items;
  final String selectedId;
  final ValueChanged<String> onNavItemTap;
  final String userEmail;
  final VoidCallback onLogout;
  final String? userRole;
  final String? activeTenantLabel;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((item) => item.visible).toList();
    final sections = <String, List<AppSidebarItem>>{};
    for (final item in visibleItems) {
      sections.putIfAbsent(item.section, () => <AppSidebarItem>[]).add(item);
    }

    return Container(
      width: 286,
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(right: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SidebarBrand(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (activeTenantLabel != null &&
                      activeTenantLabel!.trim().isNotEmpty) ...[
                    _ActiveTenantCard(
                      label: activeTenantLabel!,
                      userRole: userRole,
                    ),
                    const SizedBox(height: 18),
                  ],
                  for (final entry in sections.entries) ...[
                    _SidebarSection(
                      title: entry.key,
                      children: entry.value
                          .map(
                            (item) => _SidebarNavItem(
                              item: item,
                              selected: item.id == selectedId,
                              onTap: () => onNavItemTap(item.id),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
          gradient: const LinearGradient(
            colors: [Color(0xFF111827), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C8CFF), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Painel do chatbot',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Operação, cobrança e fluxos em um só lugar',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurfaceSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.insights_rounded, size: 15, color: _kActive),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Painel modular para operação, clientes e administração',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTenantCard extends StatelessWidget {
  const _ActiveTenantCard({
    required this.label,
    this.userRole,
  });

  final String label;
  final String? userRole;

  @override
  Widget build(BuildContext context) {
    final normalizedRole = (userRole ?? '').trim().toLowerCase();
    final isSuperadmin = normalizedRole.contains('super');
    final isSystemAdmin = normalizedRole.contains('system');
    final scopeLabel = isSystemAdmin
        ? 'Administrador do sistema'
        : isSuperadmin
            ? 'Superadministrador'
            : 'Cliente';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _kHover,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  scopeLabel,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.radar_rounded, color: _kSuccess, size: 15),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Cliente em foco',
            style: TextStyle(
              color: _kSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: _kSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        ...children,
      ],
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
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? _kSurface
                  : (_hovering ? _kHover.withValues(alpha: 0.82) : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? const Color(0xFF2E3C58) : Colors.transparent,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : _hovering
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? _kHover : _kSurfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.item.icon,
                    size: 18,
                    color: selected ? _kActive : _kMuted,
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
                          color: selected ? Colors.white : _kText,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (widget.item.helper != null &&
                          widget.item.helper!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.item.helper!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kSubtle,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: selected ? _kActive : _kSubtle,
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
    final nameSeed = email.isNotEmpty ? email[0].toUpperCase() : 'A';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C8CFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              nameSeed,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
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
                    color: _kText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _humanizeRoleLabel(role),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kSubtle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onLogout,
            tooltip: 'Sair',
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
              color: _kMuted,
            ),
          ),
        ],
      ),
    );
  }
}
