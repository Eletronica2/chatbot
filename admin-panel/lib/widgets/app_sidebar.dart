import 'package:flutter/material.dart';

const _kBg = Color(0xFF0F172A);
const _kHover = Color(0xFF1E293B);
const _kActive = Color(0xFF818CF8);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kText = Color(0xFFCBD5E1);

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onNavItemTap,
    required this.userEmail,
    required this.onLogout,
  });

  final int selectedIndex;
  final ValueChanged<int> onNavItemTap;
  final String userEmail;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarLogo(),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Conversas',
            isActive: selectedIndex == 0,
            onTap: () => onNavItemTap(0),
          ),
          _NavItem(
            icon: Icons.tune_rounded,
            label: 'Configurações',
            isActive: selectedIndex == 1,
            onTap: () => onNavItemTap(1),
          ),
          const Spacer(),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 12),
          _UserFooter(email: userEmail, onLogout: onLogout),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'ChatBot',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' Admin',
                  style: TextStyle(color: _kSubtle, fontSize: 16, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active ? _kHover : (_hovering ? _kHover.withOpacity(0.5) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: active
                  ? const Border(left: BorderSide(color: _kActive, width: 3))
                  : const Border(left: BorderSide(color: Colors.transparent, width: 3)),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: active ? _kActive : _kMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: active ? Colors.white : _kText,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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
  const _UserFooter({required this.email, required this.onLogout});

  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFF4F46E5),
              child: Text(
                email.isNotEmpty ? email[0].toUpperCase() : 'A',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                email,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kText, fontSize: 12),
              ),
            ),
            InkWell(
              onTap: onLogout,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.logout_rounded, color: _kSubtle, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
