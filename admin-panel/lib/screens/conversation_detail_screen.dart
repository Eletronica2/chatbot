import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/conversation.dart';
import '../models/conversation_group.dart';
import '../models/flow_state.dart';
import '../models/message.dart';
import '../models/quick_reply.dart';
import '../models/tenant_user.dart';
import '../services/auth_service.dart';
import '../services/conversation_group_service.dart';
import '../services/conversation_service.dart';
import '../services/quick_reply_service.dart';
import '../services/tenant_user_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/message_bubble.dart';
import '../widgets/premium_ui.dart';
import '../widgets/ui_kit.dart';

class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.conversation,
    this.embedded = false,
    this.onClose,
    this.onConversationUpdated,
  });

  final Conversation conversation;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<Conversation>? onConversationUpdated;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  late Conversation _conversation;
  List<ChatMessageModel> _messages = <ChatMessageModel>[];
  bool _loadingMessages = true;
  String? _messagesError;

  FlowStateModel? _flowState;
  bool _loadingFlow = true;

  List<ConversationGroup> _groups = const [];
  List<TenantUserModel> _team = const [];
  List<QuickReply> _quickReplies = const [];

  final TextEditingController _replyCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _assignmentBusy = false;
  bool _showContext = true;
  bool _contextSeeded = false;
  bool _showQuickPicker = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _replyCtrl.addListener(_onReplyChanged);
    _loadMessages();
    _loadFlowState();
    _loadAssignmentMeta();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_contextSeeded) {
      _contextSeeded = true;
      final width = MediaQuery.sizeOf(context).width;
      _showContext = width >= AppLayout.contextPanelMinViewport;
    }
  }

  @override
  void didUpdateWidget(covariant ConversationDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _conversation = widget.conversation;
      _replyCtrl.clear();
      _showQuickPicker = false;
      _loadMessages();
      _loadFlowState();
      _loadAssignmentMeta();
    } else if (oldWidget.conversation != widget.conversation) {
      _conversation = widget.conversation;
    }
  }

  @override
  void dispose() {
    _replyCtrl.removeListener(_onReplyChanged);
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onReplyChanged() {
    final show = _slashQuery() != null;
    if (show != _showQuickPicker) {
      setState(() => _showQuickPicker = show);
    } else if (show) {
      setState(() {});
    }
  }

  String? _slashQuery() {
    final text = _replyCtrl.text;
    final slash = text.lastIndexOf('/');
    if (slash < 0) return null;
    if (slash > 0 && text[slash - 1] != ' ' && text[slash - 1] != '\n') {
      return null;
    }
    final fragment = text.substring(slash + 1);
    if (fragment.contains(' ') || fragment.contains('\n')) return null;
    return fragment.toLowerCase();
  }

  List<QuickReply> get _filteredQuickReplies {
    final q = _slashQuery();
    if (q == null) return const [];
    return _quickReplies.where((item) {
      if (q.isEmpty) return true;
      return item.bareShortcut.contains(q) ||
          item.title.toLowerCase().contains(q);
    }).take(8).toList();
  }

  void _insertQuickReply(QuickReply reply) {
    final text = _replyCtrl.text;
    final slash = text.lastIndexOf('/');
    if (slash < 0) {
      _replyCtrl.text = reply.content;
    } else {
      _replyCtrl.text = '${text.substring(0, slash)}${reply.content}';
    }
    _replyCtrl.selection = TextSelection.collapsed(
      offset: _replyCtrl.text.length,
    );
    setState(() => _showQuickPicker = false);
  }

  Future<void> _loadAssignmentMeta() async {
    final tenantId = authService.tenantId ?? '';
    try {
      final groups = await conversationGroupService.listGroups().catchError(
            (_) => <ConversationGroup>[],
          );
      final team = tenantId.isEmpty
          ? <TenantUserModel>[]
          : await tenantUserService.listUsers(tenantId).catchError(
                (_) => <TenantUserModel>[],
              );
      final replies = await quickReplyService.listQuickReplies().catchError(
            (_) => <QuickReply>[],
          );
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _team = team;
        _quickReplies = replies;
      });
    } catch (_) {}
  }

  void _applyConversation(Conversation updated) {
    setState(() => _conversation = updated);
    widget.onConversationUpdated?.call(updated);
  }

  Future<void> _assume() async {
    setState(() => _assignmentBusy = true);
    try {
      final updated = await conversationService.assume(_conversation.id);
      if (!mounted) return;
      _applyConversation(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa assumida.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível assumir: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _assignmentBusy = false);
    }
  }

  Future<void> _returnToAi() async {
    setState(() => _assignmentBusy = true);
    try {
      final updated = await conversationService.returnToAi(_conversation.id);
      if (!mounted) return;
      _applyConversation(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa devolvida para a IA.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível devolver: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _assignmentBusy = false);
    }
  }

  Future<void> _transfer() async {
    if (_team.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum membro da equipe disponível.')),
      );
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Transferir para',
            style: TextStyle(color: AppColors.text),
          ),
          children: [
            for (final user in _team)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, user.userId),
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName : user.email,
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
          ],
        );
      },
    );
    if (selected == null || selected.isEmpty) return;
    setState(() => _assignmentBusy = true);
    try {
      final updated = await conversationService.transfer(
        conversationId: _conversation.id,
        userId: selected,
      );
      if (!mounted) return;
      _applyConversation(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa transferida.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível transferir: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _assignmentBusy = false);
    }
  }

  Future<void> _setGroup(String? groupId) async {
    setState(() => _assignmentBusy = true);
    try {
      final updated = await conversationService.setGroup(
        conversationId: _conversation.id,
        groupId: groupId,
      );
      if (!mounted) return;
      _applyConversation(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível alterar o grupo: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _assignmentBusy = false);
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loadingMessages = true;
      _messagesError = null;
    });

    try {
      final messages =
          await conversationService.fetchMessages(_conversation.id);
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
      final state = await conversationService.fetchFlowState(_conversation.id);
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
          duration: AppMotion.pageOf(context),
          curve: AppMotion.pageCurve,
        );
      }
    });
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await conversationService.sendReply(_conversation.id, text);
      _replyCtrl.clear();
      await _loadMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resposta enviada com sucesso.')),
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
      if (mounted) setState(() => _sending = false);
    }
  }

  void _handleBack() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    Navigator.of(context).pop();
  }

  Widget _buildBody({required bool allowContextRail}) {
    return Column(
      children: [
        _ConversationHeader(
          conversation: _conversation,
          groups: _groups,
          busy: _assignmentBusy,
          onBack: _handleBack,
          onRefresh: () {
            _loadMessages();
            _loadFlowState();
            _loadAssignmentMeta();
          },
          onAssume: _assume,
          onTransfer: _transfer,
          onReturnToAi: _returnToAi,
          onGroupChanged: _setGroup,
          contextVisible: _showContext,
          onToggleContext: () => setState(() => _showContext = !_showContext),
          showBack: !widget.embedded || !AppBreakpoints.useInboxSplit(context),
        ),
        if (_conversation.humanHandoffPending) const _HandoffBanner(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canShowRail = allowContextRail &&
                  constraints.maxWidth >= AppLayout.contextPanelMinDetailWidth;
              final open = _showContext && canShowRail;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ChatPanel(
                      messages: _messages,
                      loading: _loadingMessages,
                      error: _messagesError,
                      scrollCtrl: _scrollCtrl,
                      replyCtrl: _replyCtrl,
                      sending: _sending,
                      onSend: _sendReply,
                      showQuickPicker: _showQuickPicker,
                      filteredQuickReplies: _filteredQuickReplies,
                      onPickQuickReply: _insertQuickReply,
                      onToggleQuickPicker: () {
                        setState(() {
                          if (_showQuickPicker) {
                            _showQuickPicker = false;
                          } else {
                            final text = _replyCtrl.text;
                            if (!text.contains('/')) {
                              final needsSpace = text.isNotEmpty &&
                                  !text.endsWith(' ') &&
                                  !text.endsWith('\n');
                              _replyCtrl.text =
                                  '$text${needsSpace ? ' ' : ''}/';
                              _replyCtrl.selection = TextSelection.collapsed(
                                offset: _replyCtrl.text.length,
                              );
                            }
                            _showQuickPicker = true;
                          }
                        });
                      },
                    ),
                  ),
                  AnimatedContainer(
                    duration: AppMotion.of(context, AppMotion.contextPanel),
                    curve: AppMotion.pageCurve,
                    width: open ? AppLayout.contextPanelWidth : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: SizedBox(
                      width: AppLayout.contextPanelWidth,
                      child: _InfoSidebar(
                        conversation: _conversation,
                        flowState: _flowState,
                        loading: _loadingFlow,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.background,
        child: _buildBody(allowContextRail: true),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: PremiumPageBackground(
        intensity: AmbientIntensity.soft,
        child: SafeArea(
          child: _buildBody(allowContextRail: true),
        ),
      ),
    );
  }
}

class _HandoffBanner extends StatelessWidget {
  const _HandoffBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(color: AppColors.warning.withValues(alpha: 0.25)),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.support_agent_rounded, color: AppColors.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cliente aguardando atendimento humano',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.conversation,
    required this.groups,
    required this.busy,
    required this.onBack,
    required this.onRefresh,
    required this.onAssume,
    required this.onTransfer,
    required this.onReturnToAi,
    required this.onGroupChanged,
    required this.contextVisible,
    required this.onToggleContext,
    required this.showBack,
  });

  final Conversation conversation;
  final List<ConversationGroup> groups;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onAssume;
  final VoidCallback onTransfer;
  final VoidCallback onReturnToAi;
  final ValueChanged<String?> onGroupChanged;
  final bool contextVisible;
  final VoidCallback onToggleContext;
  final bool showBack;

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

  @override
  Widget build(BuildContext context) {
    final me = authService.currentUser?.userId;
    final isMine = me != null &&
        me.isNotEmpty &&
        conversation.assignedUserId == me;
    final onAi = conversation.isAssignedToAi;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Voltar',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              CircleAvatar(
                radius: 14,
                backgroundColor: _avatarColor(conversation.phoneNumber)
                    .withValues(alpha: 0.22),
                child: Text(
                  _initials(conversation.phoneNumber),
                  style: TextStyle(
                    color: _avatarColor(conversation.phoneNumber),
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
                    Text(
                      conversation.phoneNumber,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Responsável: ${conversation.isAssignedToAi ? 'IA' : conversation.assigneeLabel}',
                      style: TextStyle(
                        color: conversation.humanHandoffPending
                            ? AppColors.warning
                            : AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: contextVisible ? 'Recolher contexto' : 'Abrir contexto',
                onPressed: onToggleContext,
                icon: Icon(
                  contextVisible
                      ? Icons.view_sidebar_rounded
                      : Icons.info_outline_rounded,
                  color: contextVisible
                      ? AppColors.primarySoft
                      : AppColors.textMuted,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: onRefresh,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: groups.any((g) => g.id == conversation.groupId)
                      ? conversation.groupId
                      : null,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Grupo',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  dropdownColor: AppColors.surface,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sem grupo'),
                    ),
                    for (final group in groups)
                      DropdownMenuItem<String?>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                  ],
                  onChanged: busy ? null : onGroupChanged,
                ),
              ),
              if (onAi || !isMine)
                OutlinedButton.icon(
                  onPressed: busy ? null : onAssume,
                  icon: const Icon(Icons.handshake_rounded, size: 16),
                  label: const Text('Assumir'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : onTransfer,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Transferir'),
              ),
              if (!onAi)
                OutlinedButton.icon(
                  onPressed: busy ? null : onReturnToAi,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('Devolver para IA'),
                ),
            ],
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
    required this.showQuickPicker,
    required this.filteredQuickReplies,
    required this.onPickQuickReply,
    required this.onToggleQuickPicker,
  });

  final List<ChatMessageModel> messages;
  final bool loading;
  final String? error;
  final ScrollController scrollCtrl;
  final TextEditingController replyCtrl;
  final bool sending;
  final VoidCallback onSend;
  final bool showQuickPicker;
  final List<QuickReply> filteredQuickReplies;
  final ValueChanged<QuickReply> onPickQuickReply;
  final VoidCallback onToggleQuickPicker;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(child: _buildMessages()),
          if (showQuickPicker && filteredQuickReplies.isNotEmpty)
            _QuickReplySuggestions(
              items: filteredQuickReplies,
              onPick: onPickQuickReply,
            ),
          _ReplyBar(
            ctrl: replyCtrl,
            sending: sending,
            onSend: onSend,
            onToggleQuickPicker: onToggleQuickPicker,
          ),
        ],
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
            'Assim que a conversa começar, as mensagens aparecerão aqui.',
      );
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return MessageBubble(message: messages[index]);
      },
    );
  }
}

class _QuickReplySuggestions extends StatelessWidget {
  const _QuickReplySuggestions({
    required this.items,
    required this.onPick,
  });

  final List<QuickReply> items;
  final ValueChanged<QuickReply> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            dense: true,
            leading: const Icon(
              Icons.flash_on_rounded,
              size: 16,
              color: AppColors.primarySoft,
            ),
            title: Text(
              item.title,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
            subtitle: Text(
              '/${item.bareShortcut}',
              style: const TextStyle(color: AppColors.textSoft, fontSize: 11),
            ),
            onTap: () => onPick(item),
          );
        },
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.ctrl,
    required this.sending,
    required this.onSend,
    required this.onToggleQuickPicker,
  });

  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onToggleQuickPicker;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Respostas rápidas (/)',
            onPressed: onToggleQuickPicker,
            icon: const Icon(
              Icons.bolt_rounded,
              color: AppColors.primarySoft,
              size: 22,
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Digite uma resposta… ou /atalho',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.lg,
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.lg,
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadius.lg,
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: sending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
              ),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Enviar'),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSidebar extends StatelessWidget {
  const _InfoSidebar({
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
    return ColoredBox(
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contexto',
              style: GoogleFonts.manrope(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _InfoBlock(
              label: 'Canal de resposta',
              value: conversation.aiEnabled
                  ? 'IA + automações'
                  : 'Atendimento humano',
            ),
            const SizedBox(height: 10),
            _InfoBlock(
              label: 'Última atualização',
              value: conversation.formattedUpdatedAt,
            ),
            const SizedBox(height: 10),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
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
              const SizedBox(height: 10),
              _InfoBlock(
                label: 'Etapa atual',
                value: flowState!.currentState,
              ),
              if (flowState!.stateData['detected_intent'] != null) ...[
                const SizedBox(height: 10),
                _InfoBlock(
                  label: 'Intenção detectada',
                  value:
                      '${flowState!.stateData['detected_intent']}'
                      '${flowState!.stateData['confidence'] != null ? ' (${((flowState!.stateData['confidence'] as num) * 100).round()}%)' : ''}',
                ),
              ],
              if (flowState!.stateData['source'] != null) ...[
                const SizedBox(height: 10),
                _InfoBlock(
                  label: 'Fonte da última resposta',
                  value: _sourceLabel(
                    flowState!.stateData['source']?.toString() ?? '',
                  ),
                ),
              ],
              if (flowState!.stateData['collected_data'] is Map &&
                  (flowState!.stateData['collected_data'] as Map)
                      .isNotEmpty) ...[
                const SizedBox(height: 10),
                _CollectedDataBlock(
                  data: Map<String, dynamic>.from(
                    flowState!.stateData['collected_data'] as Map,
                  ),
                ),
              ],
              if (flowState!.stateData['smart_reentry'] == true) ...[
                const SizedBox(height: 10),
                const _TagChip(
                  label: 'Retomou fluxo após pergunta fora de contexto',
                  color: AppColors.warning,
                ),
              ],
              const SizedBox(height: 10),
              _InfoBlock(
                label: 'Atualizada em',
                value: DateFormat('dd/MM/yyyy HH:mm')
                    .format(flowState!.updatedAt.toLocal()),
              ),
            ],
          ],
        ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.borderSubtle),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.borderSubtle),
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
