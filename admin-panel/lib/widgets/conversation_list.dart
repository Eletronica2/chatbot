import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/app_tokens.dart';

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.conversations,
    required this.onSelectConversation,
  });

  final List<Conversation> conversations;
  final ValueChanged<Conversation> onSelectConversation;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _ConversationTile(
            conversation: conversations[index],
            onTap: () => onSelectConversation(conversations[index]),
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
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hovered = false;

  static const List<Color> _palette = <Color>[
    Color(0xFF7C8CFF),
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

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final hasUnread = conversation.unreadCount > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: AppRadius.lg,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceAlt : AppColors.surface,
            borderRadius: AppRadius.lg,
            border: Border.all(
              color: hasUnread
                  ? AppColors.primary.withValues(alpha: 0.26)
                  : AppColors.border,
            ),
            boxShadow: _hovered ? AppShadows.hover : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _avatarColor(conversation.phoneNumber),
                    child: Text(
                      _initials(conversation.phoneNumber),
                      style: const TextStyle(
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
                        border: Border.all(color: AppColors.surface, width: 2),
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
                            conversation.phoneNumber,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.formattedUpdatedAt,
                          style: TextStyle(
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
                            style: const TextStyle(
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
                              style: const TextStyle(
                                color: Colors.white,
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
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSoft,
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
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
