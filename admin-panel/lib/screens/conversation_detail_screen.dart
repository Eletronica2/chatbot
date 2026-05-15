import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/conversation.dart';
import '../models/flow_state.dart';
import '../models/message.dart';
import '../services/conversation_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/message_bubble.dart';
import '../widgets/ui_kit.dart';

class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.conversation,
  });

  final Conversation conversation;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  List<ChatMessageModel> _messages = <ChatMessageModel>[];
  bool _loadingMessages = true;
  String? _messagesError;

  FlowStateModel? _flowState;
  bool _loadingFlow = true;

  final TextEditingController _replyCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadFlowState();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loadingMessages = true;
      _messagesError = null;
    });

    try {
      final messages =
          await conversationService.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
      _scrollToBottom();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _messagesError = err.toString();
        _loadingMessages = false;
      });
    }
  }

  Future<void> _loadFlowState() async {
    setState(() => _loadingFlow = true);
    try {
      final state =
          await conversationService.fetchFlowState(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _flowState = state;
        _loadingFlow = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFlow = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await conversationService.sendReply(widget.conversation.id, text);
      _replyCtrl.clear();
      await _loadMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resposta enviada com sucesso.'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar a mensagem: $err'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _ConversationHeader(
                conversation: widget.conversation,
                onBack: () => Navigator.of(context).pop(),
                onRefresh: () {
                  _loadMessages();
                  _loadFlowState();
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showSidebar = constraints.maxWidth >= 1120;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _ChatPanel(
                            messages: _messages,
                            loading: _loadingMessages,
                            error: _messagesError,
                            scrollCtrl: _scrollCtrl,
                            replyCtrl: _replyCtrl,
                            sending: _sending,
                            onSend: _sendReply,
                          ),
                        ),
                        if (showSidebar) ...[
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 320,
                            child: _InfoPanel(
                              conversation: widget.conversation,
                              flowState: _flowState,
                              loading: _loadingFlow,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.conversation,
    required this.onBack,
    required this.onRefresh,
  });

  final Conversation conversation;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

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
    return AppPanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textMuted),
          ),
          const SizedBox(width: 6),
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
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
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
                Text(
                  conversation.phoneNumber,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusChip(
                      label: conversation.aiEnabled ? 'IA ativa' : 'Atendimento humano',
                      icon: conversation.aiEnabled
                          ? Icons.auto_awesome_rounded
                          : Icons.support_agent_rounded,
                      backgroundColor: conversation.aiEnabled
                          ? AppColors.success.withValues(alpha: 0.14)
                          : AppColors.warning.withValues(alpha: 0.16),
                      foregroundColor: conversation.aiEnabled
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    AppStatusChip(
                      label: 'Atualização ${conversation.formattedUpdatedAt}',
                      icon: Icons.schedule_rounded,
                      backgroundColor: AppColors.surfaceAlt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.loading,
    required this.error,
    required this.scrollCtrl,
    required this.replyCtrl,
    required this.sending,
    required this.onSend,
  });

  final List<ChatMessageModel> messages;
  final bool loading;
  final String? error;
  final ScrollController scrollCtrl;
  final TextEditingController replyCtrl;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.lg,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.whatsappPattern,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0E1524), Color(0xFF0B0F1A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: CustomPaint(
                        painter: _ChatPatternPainter(),
                      ),
                    ),
                  ),
                  Positioned.fill(child: _buildMessages()),
                ],
              ),
            ),
            _ReplyBar(
              ctrl: replyCtrl,
              sending: sending,
              onSend: onSend,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar a conversa',
        message: error!,
      );
    }
    if (messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.mark_chat_read_rounded,
        title: 'Nenhuma mensagem ainda',
        message:
            'Assim que a conversa começar, as mensagens aparecerão aqui no formato do WhatsApp.',
      );
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return MessageBubble(message: messages[index]);
      },
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.ctrl,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Digite uma resposta para enviar ao cliente...',
                prefixIcon: Icon(Icons.chat_rounded),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(sending ? 'Enviando...' : 'Enviar'),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.conversation,
    required this.flowState,
    required this.loading,
  });

  final Conversation conversation;
  final FlowStateModel? flowState;
  final bool loading;

  String _sourceLabel(String source) {
    switch (source) {
      case 'flow':
        return 'Fluxo automatizado';
      case 'ai':
        return 'IA (Gemini)';
      case 'ai_fallback':
        return 'IA (fallback de fluxo)';
      case 'subscription':
        return 'Bloqueio de assinatura';
      default:
        return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Resumo da conversa',
            subtitle:
                'Entenda rapidamente como o chatbot está conduzindo o atendimento desta pessoa.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoBlock(
            label: 'Canal de resposta',
            value: conversation.aiEnabled ? 'IA + automações' : 'Atendimento humano',
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoBlock(
            label: 'Última atualização',
            value: conversation.formattedUpdatedAt,
          ),
          const SizedBox(height: AppSpacing.md),
          if (loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ))
          else if (flowState == null)
            const _InfoBlock(
              label: 'Automação ativa',
              value: 'Nenhuma automação ativa no momento',
            )
          else ...[
            _InfoBlock(
              label: 'Automação ativa',
              value: flowState!.flowName,
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoBlock(
              label: 'Etapa atual',
              value: flowState!.currentState,
            ),
            if (flowState!.stateData['detected_intent'] != null) ...[
              const SizedBox(height: AppSpacing.md),
              _InfoBlock(
                label: 'Intenção detectada',
                value: '${flowState!.stateData['detected_intent']}'
                    '${flowState!.stateData['confidence'] != null ? ' (${((flowState!.stateData['confidence'] as num) * 100).round()}%)' : ''}',
              ),
            ],
            if (flowState!.stateData['source'] != null) ...[
              const SizedBox(height: AppSpacing.md),
              _InfoBlock(
                label: 'Fonte da última resposta',
                value: _sourceLabel(flowState!.stateData['source']?.toString() ?? ''),
              ),
            ],
            if (flowState!.stateData['collected_data'] is Map &&
                (flowState!.stateData['collected_data'] as Map).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _CollectedDataBlock(
                data: Map<String, dynamic>.from(
                  flowState!.stateData['collected_data'] as Map,
                ),
              ),
            ],
            if (flowState!.stateData['smart_reentry'] == true) ...[
              const SizedBox(height: AppSpacing.md),
              _TagChip(
                label: 'Retomou fluxo após pergunta fora de contexto',
                color: AppColors.warning,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _InfoBlock(
              label: 'Atualizada em',
              value: DateFormat('dd/MM/yyyy HH:mm')
                  .format(flowState!.updatedAt.toLocal()),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSoft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectedDataBlock extends StatelessWidget {
  const _CollectedDataBlock({required this.data});

  final Map<String, dynamic> data;

  static const Map<String, String> _labels = {
    'nome_cliente': 'Nome',
    'endereco_entrega': 'Endereço de entrega',
    'info_retirada': 'Info retirada',
    'sabores_pedido': 'Sabores escolhidos',
    'forma_pagamento': 'Forma de pagamento',
  };

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dados coletados',
            style: TextStyle(
              color: AppColors.textSoft,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map((e) {
            final label = _labels[e.key] ?? e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label: ',
                    style: const TextStyle(
                      color: AppColors.textSoft,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${e.value}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.loop_rounded, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const spacing = 34.0;
    for (double x = -spacing; x < size.width + spacing; x += spacing) {
      for (double y = -spacing; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 10, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
