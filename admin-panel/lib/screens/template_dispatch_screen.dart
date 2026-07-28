import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/whatsapp_account.dart';
import '../models/whatsapp_template.dart';
import '../services/auth_service.dart';
import '../services/whatsapp_account_service.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/coexistence_wizard.dart';
import '../widgets/whatsapp_meta_panels.dart';

class TemplateDispatchScreen extends StatefulWidget {
  const TemplateDispatchScreen({super.key});

  static const String defaultRecipientLabel = '+55 34 99266-5547';
  static const String defaultRecipientE164 = '5534992665547';

  @override
  State<TemplateDispatchScreen> createState() => _TemplateDispatchScreenState();
}

class _TemplateDispatchScreenState extends State<TemplateDispatchScreen> {
  final _recipientController = TextEditingController(
    text: TemplateDispatchScreen.defaultRecipientLabel,
  );

  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _selectedAccountKey;
  String? _selectedTemplateName;
  List<WhatsAppAccountModel> _accounts = <WhatsAppAccountModel>[];
  List<WhatsAppTemplateModel> _templates = <WhatsAppTemplateModel>[];
  List<TextEditingController> _bodyParamControllers = <TextEditingController>[];

  String get _tenantId => authService.tenantId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _recipientController.dispose();
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
    if (_selectedTemplateName == null) return null;
    for (final template in _templates) {
      if (template.name == _selectedTemplateName) return template;
    }
    return null;
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

  Future<void> _load() async {
    if (_tenantId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Tenant nao identificado. Faca login novamente.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final accounts = await whatsAppAccountService.listAccounts(_tenantId);
      WhatsAppAccountModel? preferred;
      if (accounts.isNotEmpty) {
        preferred = accounts.where((item) => item.displayPhoneNumber.contains('31951773')).isNotEmpty
            ? accounts.firstWhere((item) => item.displayPhoneNumber.contains('31951773'))
            : (accounts.where((item) => item.isDefault).isNotEmpty
                ? accounts.firstWhere((item) => item.isDefault)
                : accounts.first);
      }

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
        if (_selectedTemplateName != null &&
            !templates.any((item) => item.name == _selectedTemplateName)) {
          _selectedTemplateName = null;
        }
        _error = accounts.isEmpty
            ? 'Nenhuma conta WhatsApp vinculada. Conecte em WhatsApp no menu lateral.'
            : (templates.isEmpty
                ? 'Nenhum modelo encontrado. Crie um modelo nesta tela (seção acima) ou aguarde aprovação da Meta.'
                : null);
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onAccountChanged(String? accountKey) async {
    if (accountKey == null || accountKey == _selectedAccountKey) return;
      setState(() {
        _selectedAccountKey = accountKey;
        _selectedTemplateName = null;
        _syncBodyParamControllers(null);
        _loading = true;
        _error = null;
      });
    try {
      final templates = await whatsAppTemplateService.listTemplates(
        _tenantId,
        accountKey: accountKey,
      );
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _error = templates.isEmpty
            ? 'Nenhum modelo encontrado para esta conta.'
            : null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      return 'Numero remetente nao registrado na Cloud API. Complete a coexistencia no Embedded Signup (QR no painel admin via HTTPS).';
    }
    if (lower.contains('131030')) {
      return 'Destinatario nao esta na lista de teste da Meta. Adicione em API Setup > To.';
    }
    if (lower.contains('session has expired') || lower.contains('error validating access token')) {
      return 'Token Meta expirado. Configure META_SYSTEM_USER_TOKEN no backend para atualizacao automatica.';
    }
    return raw;
  }

  Future<void> _sendSelectedTemplate() async {
    final template = _selectedTemplate;
    if (template == null) return;

    final recipient = _normalizeRecipient(_recipientController.text.trim());
    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um destinatario valido.')),
      );
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
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
                ? 'Token atualizado automaticamente. Template enviado para $recipientLabel.'
                : (messageId == null || messageId.isEmpty
                    ? 'Template ${template.name} enviado para $recipientLabel.'
                    : 'Enviado! message_id: $messageId'),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      final message = _friendlyError('$err');
      setState(() => _error = message);
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
    final account = _selectedAccount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(account),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_error != null) ...[
              _buildErrorCard(_error!),
              if (_templates.isEmpty && _selectedAccountKey == '507137542482993') ...[
                const SizedBox(height: 10),
                _buildCoexistenceBanner(),
              ],
              const SizedBox(height: 12),
            ] else if (_templates.isEmpty && _selectedAccountKey == '507137542482993') ...[
              _buildCoexistenceBanner(),
              const SizedBox(height: 12),
            ],
            if (_tenantId.isNotEmpty && _selectedAccountKey != null) ...[
              WhatsAppTemplatesSection(
                tenantId: _tenantId,
                accountKey: _selectedAccountKey,
                cardColor: AppColors.surface,
                borderColor: AppColors.border,
                textColor: AppColors.text,
                mutedColor: AppColors.textMuted,
                accentColor: AppColors.primary,
                showExistingList: false,
                onCreated: _load,
              ),
              const SizedBox(height: 16),
            ],
            _buildFormCard(),
            const SizedBox(height: 16),
            _buildTemplatesSection(),
            if (_bodyParamControllers.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildBodyParametersSection(),
            ],
            const SizedBox(height: 20),
            _buildSendButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard(WhatsAppAccountModel? account) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modelos WhatsApp',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crie modelos oficiais na Meta, acompanhe o status (PENDING/APPROVED) e dispare testes para o destinatário cadastrado.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          if (account != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _infoChip('WABA', account.accountKey),
                _infoChip('Phone Number ID', account.phoneNumberId),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _loading || _sending ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Atualizar lista'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2. Remetente e destinatário',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _accounts.any((a) => a.accountKey == _selectedAccountKey)
                ? _selectedAccountKey
                : null,
            decoration: const InputDecoration(
              labelText: 'Conta remetente (numero WhatsApp)',
              border: OutlineInputBorder(),
            ),
            items: _accounts
                .map(
                  (account) => DropdownMenuItem<String>(
                    value: account.accountKey,
                    child: Text(
                      '${account.displayPhoneNumber}${account.isDefault ? ' (padrao)' : ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: _sending ? null : _onAccountChanged,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _recipientController,
            enabled: !_sending,
            decoration: const InputDecoration(
              labelText: 'Destinatario',
              hintText: TemplateDispatchScreen.defaultRecipientLabel,
              border: OutlineInputBorder(),
              helperText: 'Numero de teste cadastrado na Meta (App Review)',
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '3. Selecione o template para disparo',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_templates.isEmpty)
            const Text(
              'Nenhum modelo disponivel para esta conta.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else
            ..._templates.map(_buildTemplateRow),
        ],
      ),
    );
  }

  Widget _buildTemplateRow(WhatsAppTemplateModel template) {
    final approved = template.status.toUpperCase() == 'APPROVED';
    final hasVariables = _bodyVariableCount(template.bodyText) > 0;
    final selectable = approved;
    final isSelected = _selectedTemplateName == template.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.borderSubtle,
        ),
      ),
      child: RadioListTile<String>(
        value: template.name,
        groupValue: _selectedTemplateName,
        onChanged: _sending || !selectable
            ? null
            : (value) {
                WhatsAppTemplateModel? selected;
                for (final item in _templates) {
                  if (item.name == value) {
                    selected = item;
                    break;
                  }
                }
                setState(() {
                  _selectedTemplateName = value;
                  _syncBodyParamControllers(selected);
                });
              },
        title: Row(
          children: [
            Expanded(
              child: Text(
                template.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(template.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                template.status,
                style: TextStyle(
                  color: _statusColor(template.status),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${template.language} | ${template.category}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (template.bodyText != null && template.bodyText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                template.bodyText!,
                style: const TextStyle(color: AppColors.textSoft, fontSize: 12, height: 1.4),
              ),
            ],
            if (!approved)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Aguarde aprovacao da Meta para habilitar envio.',
                  style: TextStyle(color: AppColors.warning, fontSize: 11),
                ),
              ),
            if (hasVariables)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Modelo com variaveis: preencha os valores abaixo antes de enviar.',
                  style: TextStyle(color: AppColors.accentBlue, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyParametersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '4. Preencha as variaveis do corpo',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cada campo substitui {{1}}, {{2}}, etc. no texto aprovado pela Meta.',
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
                decoration: InputDecoration(
                  labelText: 'Variavel {{${index + 1}}}',
                  hintText: 'Valor para {{${index + 1}}}',
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _canSend ? _sendSelectedTemplate : null,
        icon: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded),
        label: Text(_sending ? 'Enviando template...' : 'Enviar template'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.surfaceSoft,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: const TextStyle(color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _buildCoexistenceBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Numero BR sem templates? Complete a coexistencia primeiro.',
            style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'O hello_world so existe na conta teste EUA. Para o BR, conecte via Embedded Signup e crie demo_bella_massa.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _tenantId.isEmpty
                  ? null
                  : () => showCoexistenceWizard(
                        context: context,
                        tenantId: _tenantId,
                        onConnected: _load,
                      ),
              icon: const Icon(Icons.help_outline_rounded, size: 16),
              label: const Text('Abrir assistente de coexistencia'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
    );
  }
}
