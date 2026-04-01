import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/flow_state.dart';
import '../models/message.dart';
import '../services/conversation_service.dart';
import '../widgets/flow_state_card.dart';
import '../widgets/message_bubble.dart';

class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState
    extends State<ConversationDetailScreen> {
  List<ChatMessageModel> _messages = [];
  bool _loadingMsgs = true;
  String? _msgError;

  FlowStateModel? _flowState;
  bool _loadingFlow = true;

  final _replyCtrl = TextEditingController();
  bool _sending = false;
  final _scrollCtrl = ScrollController();

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
      _loadingMsgs = true;
      _msgError = null;
    });
    try {
      final msgs =
          await conversationService.fetchMessages(widget.conversation.id);
      setState(() {
        _messages = msgs;
        _loadingMsgs = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _msgError = e.toString();
        _loadingMsgs = false;
      });
    }
  }

  Future<void> _loadFlowState() async {
    setState(() => _loadingFlow = true);
    try {
      final state =
          await conversationService.fetchFlowState(widget.conversation.id);
      setState(() {
        _flowState = state;
        _loadingFlow = false;
      });
    } catch (_) {
      setState(() => _loadingFlow = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _TopBar(
            conversation: widget.conversation,
            onBack: () => Navigator.of(context).pop(),
            onRefresh: () {
              _loadMessages();
              _loadFlowState();
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _ChatArea(
                        messages: _messages,
                        loading: _loadingMsgs,
                        error: _msgError,
                        scrollCtrl: _scrollCtrl,
                        replyCtrl: _replyCtrl,
                        sending: _sending,
                        onSend: _sendReply,
                      ),
                    ),
                    if (wide)
                      Container(
                        width: 300,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                              left: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: _InfoPanel(
                          conversation: widget.conversation,
                          flowState: _flowState,
                          loading: _loadingFlow,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Top bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.conversation,
    required this.onBack,
    required this.onRefresh,
  });

  final Conversation conversation;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  static const _palette = [
    Color(0xFF4F46E5), Color(0xFF0EA5E9), Color(0xFF10B981),
    Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF8B5CF6),
  ];

  Color _avatarColor(String p) => _palette[p.hashCode.abs() % _palette.length];

  String _initials(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 2) return d.substring(d.length - 2);
    return phone.length >= 2 ? phone.substring(phone.length - 2) : phone;
  }

  @override
  Widget build(BuildContext context) {
    final phone = conversation.phoneNumber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
            color: const Color(0xFF64748B),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: _avatarColor(phone),
                child: Text(
                  _initials(phone),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
              Positioned(
                bottom: -1,
                right: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: conversation.aiEnabled
                        ? const Color(0xFF10B981)
                        : const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phone,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF0F172A)),
                ),
                Text(
                  conversation.aiEnabled ? 'IA ativa' : 'Atendimento humano',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          _BarAction(
            icon: Icons.refresh_rounded,
            label: 'Atualizar',
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Chat Area â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ChatArea extends StatelessWidget {
  const _ChatArea({
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
    return Column(
      children: [
        Expanded(child: _buildMessages(context)),
        _ReplyBar(ctrl: replyCtrl, sending: sending, onSend: onSend),
      ],
    );
  }

  Widget _buildMessages(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 36),
            const SizedBox(height: 10),
            Text('Falha ao carregar mensagens',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(error!, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ],
        ),
      );
    }
    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 40, color: Color(0xFFCBD5E1)),
            SizedBox(height: 10),
            Text(
              'Nenhuma mensagem ainda',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      itemCount: messages.length,
      itemBuilder: (_, i) => MessageBubble(message: messages[i]),
    );
  }
}

// â”€â”€â”€ Reply Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: 4,
              minLines: 1,
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: 'Responder como agente...',
                hintStyle: const TextStyle(
                    fontSize: 14, color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Color(0xFF4F46E5), width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(sending: sending, onSend: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onSend});
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: sending ? null : onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: sending
              ? const LinearGradient(
                  colors: [Color(0xFF94A3B8), Color(0xFF64748B)])
              : const LinearGradient(
                  colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: sending
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded,
                  color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Info Panel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.conversation,
    required this.flowState,
    required this.loading,
  });

  final Conversation conversation;
  final FlowStateModel? flowState;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTATO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(label: 'Telefone', value: conversation.phoneNumber),
          _InfoRow(
            label: 'IA',
            value: conversation.aiEnabled ? 'Habilitada' : 'Desabilitada',
            badge: conversation.aiEnabled
                ? const _Badge('IA', Color(0xFFECFDF5), Color(0xFF10B981))
                : const _Badge('Humano', Color(0xFFF1F5F9), Color(0xFF64748B)),
          ),
          _InfoRow(
              label: 'Atualizado', value: conversation.formattedUpdatedAt),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 20),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (flowState != null)
            FlowStateCard(flowState: flowState!)
          else
            const Text(
              'Fluxo não disponível',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.badge});
  final String label;
  final String value;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500),
            ),
          ),
          badge ??
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        label,
        style: TextStyle(
            color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}


