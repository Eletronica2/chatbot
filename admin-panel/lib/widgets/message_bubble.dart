import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../theme/app_tokens.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
  });

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final timestamp = DateFormat('HH:mm').format(message.createdAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isUser) ...[
            _BubbleAvatar(
              backgroundColor: const Color(0xFF20304E),
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.textMuted,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.whatsappBubble
                        : AppColors.whatsappReply,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 6 : 18),
                      bottomRight: Radius.circular(isUser ? 18 : 6),
                    ),
                    border: Border.all(
                      color: isUser
                          ? AppColors.border
                          : AppColors.primaryStrong.withValues(alpha: 0.48),
                    ),
                    boxShadow: AppShadows.hover,
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timestamp,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!isUser) ...[
            const SizedBox(width: 10),
            _BubbleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.16),
              icon: Icons.smart_toy_rounded,
              iconColor: AppColors.primarySoft,
            ),
          ],
        ],
      ),
    );
  }
}

class _BubbleAvatar extends StatelessWidget {
  const _BubbleAvatar({
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
  });

  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, size: 16, color: iconColor),
    );
  }
}
