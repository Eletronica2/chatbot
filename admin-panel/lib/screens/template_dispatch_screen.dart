import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/whatsapp_account.dart';
import '../models/whatsapp_template.dart';
import '../services/auth_service.dart';
import '../services/whatsapp_account_service.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';
import '../widgets/whatsapp_meta_panels.dart';

/// Templates WhatsApp — listagem Meta + disparo pontual (sem campanhas).
class TemplateDispatchScreen extends StatefulWidget {
  const TemplateDispatchScreen({super.key});

  static const String defaultRecipientLabel = '+55 34 99266-5547';
  static const String defaultRecipientE164 = '5534992665547';
  static const double _kSplit = 1100;

  @override
  State<TemplateDispatchScreen> createState() => _TemplateDispatchScreenState();
}

class _TemplateDispatchScreenState extends State<TemplateDispatchScreen> {
  final _recipientController = TextEditingController(
    text: TemplateDispatchScreen.defaultRecipientLabel,
  );
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _compactDetailOpen = false;
  bool _createExpanded = false;
  String? _listError;
  String? _sendError;
  String? _selectedAccountKey;
  String? _selectedKey; // name::language
  String? _statusFilter; // null = all; else Meta status uppercase
  List<WhatsAppAccountModel> _accounts = <WhatsAppAccountModel>[];
  List<WhatsAppTemplateModel> _templates = <WhatsAppTemplateModel>[];
  List<TextEditingController> _bodyParamControllers = <TextEditingController>[];

  String get _tenantId => authService.tenantId ?? '';

  static String _keyOf(WhatsAppTemplateModel t) => '${t.name}::${t.language}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _searchCtrl.dispose();
    _disposeBodyParamControllers();
    super.dispose();
  }

  void _disposeBodyParamControllers() {
    for (final controller in _bodyParamControllers) {
      controller.dispose();
    }
    _bodyParamControllers = <TextEditingController>[];
  }

  int _bodyVariableCount(String? bodyText) {
    if (bodyText == null || bodyText.isEmpty) return 0;
    final matches = RegExp(r'\{\{(\d+)\}\}').allMatches(bodyText);
    if (matches.isEmpty) return 0;
    var max = 0;
    for (final match in matches) {
      final value = int.tryParse(match.group(1) ?? '') ?? 0;
      if (value > max) max = value;
    }
    return max;
  }

  void _syncBodyParamControllers(WhatsAppTemplateModel? template) {
    _disposeBodyParamControllers();
    final count = _bodyVariableCount(template?.bodyText);
    _bodyParamControllers = List<TextEditingController>.generate(
      count,
      (_) => TextEditingController(),
    );
  }

  WhatsAppAccountModel? get _selectedAccount {
    if (_selectedAccountKey == null) return null;
    for (final account in _accounts) {
      if (account.accountKey == _selectedAccountKey) return account;
    }
    return null;
  }

  WhatsAppTemplateModel? get _selectedTemplate {
    if (_selectedKey == null) return null;
    for (final template in _templates) {
      if (_keyOf(template) == _selectedKey) return template;
    }
    return null;
  }

  List<WhatsAppTemplateModel> get _filteredTemplates {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _templates.where((t) {
      if (_statusFilter != null && t.status.toUpperCase() != _statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.language.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q) ||
          t.status.toLowerCase().contains(q) ||
          (t.bodyText?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Set<String> get _statusOptions {
    return _templates.map((t) => t.status.toUpperCase()).toSet();
  }

  bool get _canSend {
    final template = _selectedTemplate;
    if (template == null || _sending || _selectedAccountKey == null) return false;
    if (template.status.toUpperCase() != 'APPROVED') return false;
    if (_recipientController.text.trim().isEmpty) return false;
    final expected = _bodyVariableCount(template.bodyText);
    if (_bodyParamControllers.length != expected) return false;
    if (expected > 0 &&
        _bodyParamControllers.any((c) => c.text.trim().isEmpty)) {
      return false;
    }
    return true;
  }

  WhatsAppAccountModel? _preferAccount(List<WhatsAppAccountModel> accounts) {
    if (accounts.isEmpty) return null;
    for (final a in accounts) {
      if (a.isDefault) return a;
    }
    return accounts.first;
  }

  Future<void> _load() async {
    if (_tenantId.isEmpty) {
      setState(() {
        _loading = false;
        _listError = 'Tenant não identificado. Faça login novamente.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _listError = null;
      _sendError = null;
    });

    try {
      final accounts = await whatsAppAccountService.listAccounts(_tenantId);
      final preferred = _preferAccount(accounts);
      final accountKey = _selectedAccountKey ?? preferred?.accountKey;
      final templates = accountKey == null
          ? <WhatsAppTemplateModel>[]
          : await whatsAppTemplateService.listTemplates(
              _tenantId,
              accountKey: accountKey,
            );

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _selectedAccountKey = accountKey;
        _templates = templates;
        if (_selectedKey != null &&
            !templates.any((item) => _keyOf(item) == _selectedKey)) {
          _selectedKey = null;
          _syncBodyParamControllers(null);
          _compactDetailOpen = false;
        }
        if (accounts.isEmpty) {
          _listError =
              'Nenhuma conta WhatsApp vinculada a este tenant. Conecte uma conta no menu WhatsApp.';
        } else if (templates.isEmpty) {
          _listError =
              'Nenhum modelo encontrado nesta conta. Crie um modelo ou aguarde aprovação da Meta.';
        } else {
          _listError = null;
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _listError = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onAccountChanged(String? accountKey) async {
    if (accountKey == null || accountKey == _selectedAccountKey) return;
    setState(() {
      _selectedAccountKey = accountKey;
      _selectedKey = null;
      _syncBodyParamControllers(null);
      _compactDetailOpen = false;
      _loading = true;
      _listError = null;
      _sendError = null;
    });
    try {
      final templates = await whatsAppTemplateService.listTemplates(
        _tenantId,
        accountKey: accountKey,
      );
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _listError = templates.isEmpty
            ? 'Nenhum modelo encontrado para esta conta.'
            : null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _listError = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectTemplate(WhatsAppTemplateModel template) {
    setState(() {
      _selectedKey = _keyOf(template);
      _syncBodyParamControllers(template);
      _sendError = null;
      _compactDetailOpen = true;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedKey = null;
      _syncBodyParamControllers(null);
      _sendError = null;
      _compactDetailOpen = false;
    });
  }

  String _normalizeRecipient(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('55')) return digits;
    return '55$digits';
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('133010') || lower.contains('not registered')) {
      return 'Número remetente não registrado na Cloud API.';
    }
    if (lower.contains('131030')) {
      return 'Destinatário não está na lista de teste da Meta (API Setup > To).';
    }
    if (lower.contains('session has expired') ||
        lower.contains('error validating access token')) {
      return 'Token Meta expirado. Atualize o token da conta no backend.';
    }
    return raw;
  }

  String _previewBody(WhatsAppTemplateModel template) {
    var text = template.bodyText ?? '';
    for (var i = 0; i < _bodyParamControllers.length; i++) {
      final value = _bodyParamControllers[i].text.trim();
      final placeholder = '{{${i + 1}}}';
      text = text.replaceAll(
        placeholder,
        value.isEmpty ? placeholder : value,
      );
    }
    return text;
  }

  Future<void> _sendSelectedTemplate() async {
    final template = _selectedTemplate;
    if (template == null) return;

    final recipient = _normalizeRecipient(_recipientController.text.trim());
    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um destinatário válido.')),
      );
      return;
    }

    setState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final result = await whatsAppTemplateService.sendTemplate(
        tenantId: _tenantId,
        templateName: template.name,
        language: template.language,
        accountKey: _selectedAccountKey,
        to: recipient,
        bodyParameters: _bodyParamControllers
            .map((controller) => controller.text.trim())
            .toList(),
      );
      if (!mounted) return;
      final messageId = result['message_id']?.toString();
      final tokenRefreshed = result['token_refreshed'] == true;
      final recipientLabel = _recipientController.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tokenRefreshed
                ? 'Token atualizado. Template enviado para $recipientLabel.'
                : (messageId == null || messageId.isEmpty
                    ? 'Template ${template.name} enviado para $recipientLabel.'
                    : 'Enviado. message_id: $messageId'),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      final message = _friendlyError('$err');
      setState(() => _sendError = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao enviar: $message')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = MediaQuery.sizeOf(context).width >= TemplateDispatchScreen._kSplit;
    final Widget body;
    if (split) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 320, child: _buildListPane()),
          Container(width: 1, color: AppColors.divider),
          Expanded(child: _buildDetailPane(showBack: false)),
        ],
      );
    } else if (_compactDetailOpen && _selectedTemplate != null) {
      body = _buildDetailPane(showBack: true);
    } else {
      body = _buildListPane();
    }

    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: body,
    );
  }

  Widget _buildListPane() {
    final filtered = _filteredTemplates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Templates',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar lista',
                    onPressed: _loading || _sending ? null : _load,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Modelos oficiais da Meta neste tenant. Disparo pontual de teste.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _accounts.any((a) => a.accountKey == _selectedAccountKey)
                    ? _selectedAccountKey
                    : null,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                decoration: _fieldDecoration('Conta WhatsApp'),
                items: _accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account.accountKey,
                        child: Text(
                          '${account.displayPhoneNumber.isNotEmpty ? account.displayPhoneNumber : account.accountKey}${account.isDefault ? ' (padrão)' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _sending || _loading ? null : _onAccountChanged,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar nome, idioma, status…',
                  hintStyle: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.backgroundElevated,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.md,
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.md,
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              if (_statusOptions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      selected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    ..._statusOptions.map(
                      (status) => _FilterChip(
                        label: status,
                        selected: _statusFilter == status,
                        color: _statusColor(status),
                        onTap: () => setState(() => _statusFilter = status),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? _EmptyList(
                      message: _listError ??
                          (_templates.isEmpty
                              ? 'Nenhum modelo nesta conta.'
                              : 'Nenhum resultado para a busca/filtro.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final template = filtered[index];
                        final selected = _selectedKey == _keyOf(template);
                        return _TemplateListTile(
                          template: template,
                          selected: selected,
                          statusColor: _statusColor(template.status),
                          variableCount: _bodyVariableCount(template.bodyText),
                          onTap: () => _selectTemplate(template),
                        );
                      },
                    ),
        ),
        if (_listError != null && _templates.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              _listError!,
              style: const TextStyle(color: AppColors.warning, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPane({required bool showBack}) {
    final template = _selectedTemplate;
    final account = _selectedAccount;

    return AppPageSwitcher(
      pageKey: template == null ? 'empty' : _keyOf(template),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                if (showBack)
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textMuted,
                  ),
                Expanded(
                  child: Text(
                    template == null ? 'Detalhe / disparo' : template.name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (template == null) ...[
                  const _EmptyDetail(),
                  const SizedBox(height: 16),
                  _buildCreateSection(),
                ] else ...[
                  _buildMetaRow(template, account),
                  const SizedBox(height: 14),
                  _WhatsAppPreviewBubble(
                    body: _previewBody(template),
                    language: template.language,
                  ),
                  if (template.status.toUpperCase() != 'APPROVED') ...[
                    const SizedBox(height: 12),
                    _HintBanner(
                      color: AppColors.warning,
                      text:
                          'Status ${template.status}: aguarde APPROVED da Meta para habilitar o envio.',
                    ),
                  ],
                  if (_bodyParamControllers.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildBodyParametersSection(),
                  ],
                  const SizedBox(height: 16),
                  _buildDispatchCard(),
                  if (_sendError != null) ...[
                    const SizedBox(height: 10),
                    _HintBanner(color: AppColors.danger, text: _sendError!),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _canSend ? _sendSelectedTemplate : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _sending ? 'Enviando…' : 'Enviar template',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        disabledBackgroundColor: AppColors.surfaceSoft,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildCreateSection(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
    WhatsAppTemplateModel template,
    WhatsAppAccountModel? account,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetaChip(
          label: template.status,
          color: _statusColor(template.status),
        ),
        _MetaChip(label: template.language),
        _MetaChip(label: template.category),
        if (template.templateId != null && template.templateId!.isNotEmpty)
          _MetaChip(label: 'id ${template.templateId}'),
        if (account != null && account.displayPhoneNumber.isNotEmpty)
          _MetaChip(label: account.displayPhoneNumber),
      ],
    );
  }

  Widget _buildBodyParametersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Variáveis do corpo',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ordem Meta: {{1}}, {{2}}, … — o preview atualiza ao digitar.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...List<Widget>.generate(_bodyParamControllers.length, (index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == _bodyParamControllers.length - 1 ? 0 : 10,
              ),
              child: TextField(
                controller: _bodyParamControllers[index],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: _fieldDecoration('Variável {{${index + 1}}}'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDispatchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Destinatário do teste',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _recipientController,
            enabled: !_sending,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: _fieldDecoration(
              'Telefone',
              helper: 'Número de teste autorizado na Meta (App Review)',
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSection() {
    if (_tenantId.isEmpty || _selectedAccountKey == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _createExpanded = !_createExpanded),
            borderRadius: AppRadius.lg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Criar modelo na Meta',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _createExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_createExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: WhatsAppTemplatesSection(
                tenantId: _tenantId,
                accountKey: _selectedAccountKey,
                cardColor: AppColors.surfaceAlt,
                borderColor: AppColors.borderSubtle,
                textColor: AppColors.text,
                mutedColor: AppColors.textMuted,
                accentColor: AppColors.primary,
                showExistingList: false,
                embedded: true,
                onCreated: _load,
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      helperStyle: const TextStyle(color: AppColors.textSoft, fontSize: 11),
      isDense: true,
      filled: true,
      fillColor: AppColors.backgroundElevated,
      border: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.md,
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: selected ? c.withValues(alpha: 0.16) : AppColors.surfaceAlt,
      borderRadius: AppRadius.pill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: selected ? c.withValues(alpha: 0.5) : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c : AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateListTile extends StatefulWidget {
  const _TemplateListTile({
    required this.template,
    required this.selected,
    required this.statusColor,
    required this.variableCount,
    required this.onTap,
  });

  final WhatsAppTemplateModel template;
  final bool selected;
  final Color statusColor;
  final int variableCount;
  final VoidCallback onTap;

  @override
  State<_TemplateListTile> createState() => _TemplateListTileState();
}

class _TemplateListTileState extends State<_TemplateListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.hoverOf(context),
        curve: AppMotion.hoverCurve,
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : (_hovered ? AppColors.surfaceAlt : AppColors.surface),
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: widget.selected
                ? AppColors.primary.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.lg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: widget.statusColor.withValues(alpha: 0.14),
                          borderRadius: AppRadius.sm,
                        ),
                        child: Text(
                          t.status,
                          style: TextStyle(
                            color: widget.statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${t.language} · ${t.category}'
                    '${widget.variableCount > 0 ? ' · {{1}}…{{${widget.variableCount}}}' : ''}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color ?? AppColors.textSoft,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, height: 1.35),
      ),
    );
  }
}

/// Preview independente (não reutiliza message_bubble da Fase 2).
class _WhatsAppPreviewBubble extends StatelessWidget {
  const _WhatsAppPreviewBubble({
    required this.body,
    required this.language,
  });

  final String body;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Preview',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                language,
                style: const TextStyle(
                  color: AppColors.textSoft,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2428),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Text(
                  body.isEmpty ? '(sem corpo BODY na Meta)' : body,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Representação visual do BODY. Não altera o payload enviado à Meta.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.campaign_outlined, color: AppColors.textSoft, size: 36),
          SizedBox(height: 12),
          Text(
            'Selecione um template',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Escolha um modelo à esquerda para ver o corpo, variáveis e disparar um teste.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
