import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/conversation.dart';
import '../theme/app_motion.dart';
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
        indent: 54,
      ),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return _ConversationTile(
          conversation: conversation,
          selected: selectedId != null && conversation.id == selectedId,
          onTap: () => onSelectConversation(conversation),
        );
      },
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
    Color(0xFF22D3EE),
    Color(0xFF8B5CF6),
    Color(0xFF2DD4BF),
    Color(0xFF60A5FA),
    Color(0xFF94A3B8),
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
    final accent = _avatarColor(conversation.phoneNumber);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.hoverOf(context),
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.primary.withValues(alpha: 0.10)
                : (_hovered
                    ? AppColors.surfaceAlt.withValues(alpha: 0.55)
                    : Colors.transparent),
            border: Border(
              left: BorderSide(
                width: 2.5,
                color: widget.selected
                    ? AppColors.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Text(
                  _initials(conversation.phoneNumber),
                  style: GoogleFonts.manrope(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                            style: GoogleFonts.manrope(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          conversation.formattedUpdatedAt,
                          style: GoogleFonts.manrope(
                            color: hasUnread
                                ? AppColors.primarySoft
                                : AppColors.textSoft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage.trim().isEmpty
                                ? 'Nenhuma mensagem ainda'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(
                              conversation.unreadCount.toString(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                color: AppColors.onPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (needsHuman || conversation.aiEnabled) ...[
                      const SizedBox(height: 4),
                      Text(
                        needsHuman
                            ? 'Aguardando humano'
                            : (conversation.aiEnabled ? 'IA ativa' : ''),
                        style: GoogleFonts.manrope(
                          color: needsHuman
                              ? AppColors.warning
                              : AppColors.accentSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
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
    );
  }
}
