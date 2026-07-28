import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/conversation.dart';
import '../theme/app_tokens.dart';

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.conversations,
    required this.onSelectConversation,
    this.selectedId,
  });

  final List<Conversation> conversations;
  final ValueChanged<Conversation> onSelectConversation;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return _ConversationTile(
            conversation: conversation,
            selected: selectedId != null && conversation.id == selectedId,
            onTap: () => onSelectConversation(conversation),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    this.selected = false,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hovered = false;

  static const List<Color> _palette = <Color>[
    Color(0xFFF5A623),
    Color(0xFF48C0FF),
    Color(0xFF19C37D),
    Color(0xFFFFB84D),
    Color(0xFFFF6B6B),
    Color(0xFF9B8CFF),
  ];

  Color _avatarColor(String phone) =>
      _palette[phone.hashCode.abs() % _palette.length];

  String _initials(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 2) return digits.substring(digits.length - 2);
    return phone.length >= 2 ? phone.substring(phone.length - 2) : phone;
  }

  String _formatPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('55') && digits.length == 13) {
      return '+${digits.substring(0, 2)} ${digits.substring(2, 4)} ${digits.substring(4, 9)}-${digits.substring(9)}';
    }
    if (digits.startsWith('55') && digits.length == 12) {
      return '+${digits.substring(0, 2)} ${digits.substring(2, 4)} ${digits.substring(4, 8)}-${digits.substring(8)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final hasUnread = conversation.unreadCount > 0;
    final needsHuman = conversation.humanHandoffPending;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: AppRadius.lg,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: (_hovered || widget.selected)
                ? AppGradients.glassPanel
                : null,
            color: (_hovered || widget.selected)
                ? null
                : AppColors.background.withValues(alpha: 0.28),
            borderRadius: AppRadius.xl,
            border: Border.all(
              color: widget.selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : needsHuman
                      ? AppColors.warning.withValues(alpha: 0.42)
                      : hasUnread
                          ? AppColors.primary.withValues(alpha: 0.24)
                          : AppColors.borderSubtle.withValues(alpha: 0.62),
            ),
            boxShadow: _hovered || widget.selected
                ? AppShadows.panelHover
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: _avatarColor(conversation.phoneNumber),
                    child: Text(
                      _initials(conversation.phoneNumber),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: conversation.aiEnabled
                            ? AppColors.success
                            : AppColors.warning,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.background,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatPhone(conversation.phoneNumber),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.formattedUpdatedAt,
                          style: GoogleFonts.inter(
                            color: hasUnread
                                ? AppColors.primarySoft
                                : AppColors.textSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage.trim().isEmpty
                                ? 'Nenhuma mensagem ainda'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(
                              conversation.unreadCount.toString(),
                              style: GoogleFonts.inter(
                                color: const Color(0xFF1A1008),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (needsHuman)
                          const _ModePill(
                            icon: Icons.support_agent_rounded,
                            label: 'Pendente atendimento',
                            color: AppColors.warning,
                          )
                        else
                          _ModePill(
                            icon: conversation.aiEnabled
                                ? Icons.auto_awesome_rounded
                                : Icons.support_agent_rounded,
                            label: conversation.aiEnabled
                                ? 'IA ativa'
                                : 'Atendimento humano',
                            color: conversation.aiEnabled
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: _hovered ? AppColors.textMuted : AppColors.textSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
