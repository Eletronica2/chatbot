import 'package:flutter/material.dart';

import '../models/whatsapp_account.dart';
import '../models/whatsapp_template.dart';
import '../services/auth_service.dart';
import '../services/whatsapp_account_service.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_tokens.dart';

class TemplateDispatchScreen extends StatefulWidget {
  const TemplateDispatchScreen({super.key});

  static const String testRecipientLabel = '+55 34 99266-5547';

  @override
  State<TemplateDispatchScreen> createState() => _TemplateDispatchScreenState();
}

class _TemplateDispatchScreenState extends State<TemplateDispatchScreen> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _accountKey;
  String? _wabaLabel;
  String? _phoneNumberId;
  List<WhatsAppTemplateModel> _templates = <WhatsAppTemplateModel>[];
  String? _sendingTemplateName;

  String get _tenantId => authService.tenantId ?? '';

  @override
  void initState() {
    super.initState();
    _load();
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
      final templates = await whatsAppTemplateService.listTemplates(_tenantId);

      WhatsAppAccountModel? account;
      try {
        final accounts = await whatsAppAccountService.listAccounts(_tenantId);
        if (accounts.isNotEmpty) {
          account = accounts.where((item) => item.isDefault).isNotEmpty
              ? accounts.firstWhere((item) => item.isDefault)
              : accounts.first;
        }
      } catch (accountErr) {
        if (templates.isEmpty) {
          throw StateError('Nao foi possivel carregar a conta WhatsApp: $accountErr');
        }
      }

      if (!mounted) return;
      setState(() {
        _accountKey = account?.accountKey;
        _wabaLabel = account?.displayPhoneNumber ?? account?.accountKey;
        _phoneNumberId = account?.phoneNumberId;
        _templates = templates;
        _error = templates.isEmpty
            ? 'Nenhum modelo encontrado. Verifique o token da conta WhatsApp em Configuracoes ou peça ao administrador.'
            : null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendTemplate(WhatsAppTemplateModel template) async {
    if (template.status.toUpperCase() != 'APPROVED') return;
    if (template.bodyText != null && template.bodyText!.contains('{{')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modelos com variaveis nao sao suportados nesta tela.'),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
      _sendingTemplateName = template.name;
      _error = null;
    });

    try {
      final result = await whatsAppTemplateService.sendTemplate(
        tenantId: _tenantId,
        templateName: template.name,
        language: template.language,
        accountKey: _accountKey,
      );
      if (!mounted) return;
      final messageId = result['message_id']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            messageId == null || messageId.isEmpty
                ? 'Template ${template.name} enviado para ${TemplateDispatchScreen.testRecipientLabel}.'
                : 'Enviado! message_id: $messageId',
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao enviar: $err')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingTemplateName = null;
        });
      }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null && _templates.isEmpty)
            _buildErrorCard(_error!)
          else ...[
            if (_error != null) ...[
              _buildErrorCard(_error!),
              const SizedBox(height: 12),
            ],
            if (_templates.isEmpty)
              _buildEmptyCard()
            else
              ..._templates.map(_buildTemplateCard),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
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
            'Disparo de teste',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Envie modelos aprovados pela Meta para o destinatario de teste cadastrado no app.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip('Destinatario', TemplateDispatchScreen.testRecipientLabel),
              if (_wabaLabel != null) _infoChip('Numero', _wabaLabel!),
              if (_phoneNumberId != null) _infoChip('Phone Number ID', _phoneNumberId!),
              if (_accountKey != null) _infoChip('WABA', _accountKey!),
            ],
          ),
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

  Widget _buildEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Nenhum modelo encontrado. Crie modelos em Clientes > WhatsApp > Modelos WhatsApp (Meta).',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _buildTemplateCard(WhatsAppTemplateModel template) {
    final approved = template.status.toUpperCase() == 'APPROVED';
    final hasVariables = template.bodyText?.contains('{{') ?? false;
    final canSend = approved && !hasVariables && !_sending;
    final isSendingThis = _sending && _sendingTemplateName == template.name;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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
          const SizedBox(height: 6),
          Text(
            '${template.language} | ${template.category}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (template.bodyText != null && template.bodyText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              template.bodyText!,
              style: const TextStyle(color: AppColors.textSoft, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: approved
                  ? (hasVariables
                      ? 'Modelo com variaveis nao suportado nesta tela'
                      : 'Enviar teste para ${TemplateDispatchScreen.testRecipientLabel}')
                  : 'Aguarde aprovacao da Meta (status APPROVED)',
              child: FilledButton.icon(
                onPressed: canSend ? () => _sendTemplate(template) : null,
                icon: isSendingThis
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(isSendingThis ? 'Enviando...' : 'Enviar teste'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.surfaceSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
