import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../services/conversation_service.dart';
import '../theme/app_tokens.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationId,
  });

  final ChatMessageModel message;
  final String conversationId;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  Uint8List? _mediaBytes;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id || oldWidget.message.mediaUrl != widget.message.mediaUrl) {
      _mediaBytes = null;
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    final msg = widget.message;
    if (!msg.hasMedia) return;
    final type = msg.messageType.toLowerCase();
    if (!{'image', 'audio', 'video', 'document', 'sticker'}.contains(type)) return;
    try {
      final bytes = await conversationService.fetchMessageMedia(widget.conversationId, msg.id);
      if (!mounted) return;
      setState(() => _mediaBytes = Uint8List.fromList(bytes));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final timestamp = DateFormat('HH:mm').format(message.createdAt.toLocal());
  final type = message.messageType.toLowerCase();

    Widget body;
    if (message.hasMedia && type == 'image' && _mediaBytes != null) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_mediaBytes!, width: 260, fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else if (message.hasMedia && type == 'audio' && _mediaBytes != null) {
      body = Text('[Áudio — reprodução no WhatsApp]', style: _textStyle());
    } else if (message.hasMedia && type == 'video') {
      body = Text(message.content.isNotEmpty ? message.content : '[Vídeo]', style: _textStyle());
    } else if (message.hasMedia && type == 'document') {
      body = Text(message.filename != null ? 'Documento: ${message.filename}' : message.content, style: _textStyle());
    } else {
      body = Text(message.content, style: _textStyle());
    }

    if (message.deliveryFailed && message.isAgent) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          const SizedBox(height: 6),
          Text(
            message.deliveryErrorHint ?? 'Não entregue no WhatsApp do cliente.',
            style: GoogleFonts.manrope(
              color: AppColors.danger,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Container(
                padding: type == 'image' && _mediaBytes != null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.surface : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isUser ? 4 : 14),
                    bottomRight: Radius.circular(isUser ? 14 : 4),
                  ),
                  border: Border.all(
                    color: isUser ? AppColors.border : AppColors.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: body,
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

  TextStyle _textStyle() {
    return GoogleFonts.manrope(color: AppColors.text, fontSize: 13.5, height: 1.45);
  }
}