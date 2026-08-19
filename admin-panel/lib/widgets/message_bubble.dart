import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../theme/app_tokens.dart';

/// Bolha de mensagem.
/// Distinção segura com os dados atuais:
/// - `user` → cliente (esquerda)
/// - demais roles → resposta do painel (direita)
/// Não rotula IA vs humano sem campo de origem por mensagem.
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.surface : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isUser ? 4 : 14),
                    bottomRight: Radius.circular(isUser ? 14 : 4),
                  ),
                  border: Border.all(
                    color: isUser
                        ? AppColors.border
                        : AppColors.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  message.content,
                  style: GoogleFonts.manrope(
                    color: AppColors.text,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
      ),
    );
  }
}
