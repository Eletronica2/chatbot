import 'package:flutter/material.dart';

import '../models/whatsapp_template.dart';
import '../services/whatsapp_onboarding_service.dart';
import '../services/whatsapp_template_service.dart';
import '../utils/meta_embedded_signup.dart';

class WhatsAppTemplatesSection extends StatefulWidget {
  const WhatsAppTemplatesSection({
    super.key,
    required this.tenantId,
    this.accountKey,
    this.cardColor = const Color(0xFF0F1421),
    this.borderColor = const Color(0xFF25304A),
    this.textColor = const Color(0xFFF5F7FF),
    this.mutedColor = const Color(0xFF98A4C0),
    this.accentColor = const Color(0xFF22D3EE),
    this.showExistingList = true,
    this.embedded = false,
    this.onCreated,
  });

  final String tenantId;
  final String? accountKey;
  final Color cardColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;
  /// When false, only the create form is shown (parent already lists templates).
  final bool showExistingList;
  /// When true, omit outer card chrome (parent already wraps).
  final bool embedded;
  final VoidCallback? onCreated;

  @override
  State<WhatsAppTemplatesSection> createState() => _WhatsAppTemplatesSectionState();
}

class _WhatsAppTemplatesSectionState extends State<WhatsAppTemplatesSection> {
  bool _loading = false;
  bool _creating = false;
  List<WhatsAppTemplateModel> _templates = <WhatsAppTemplateModel>[];
  final _nameCtrl = TextEditingController(text: 'boas_vindas_atendimento');
  final _bodyCtrl = TextEditingController(
    text: 'Ola! Bem-vindo ao atendimento automatizado da sua empresa.',
  );
  String _language = 'pt_BR';
  String _category = 'UTILITY';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.showExistingList) {
      _loadTemplates();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      final items = await whatsAppTemplateService.listTemplates(
        widget.tenantId,
        accountKey: widget.accountKey,
      );
      if (!mounted) return;
      setState(() {
        _templates = items;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTemplate() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await whatsAppTemplateService.createTemplate(
        tenantId: widget.tenantId,
        name: _nameCtrl.text.trim(),
        language: _language,
        category: _category,
        bodyText: _bodyCtrl.text.trim(),
        accountKey: widget.accountKey,
      );
      if (widget.showExistingList) {
        await _loadTemplates();
      }
      widget.onCreated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modelo enviado à Meta. Status inicial: PENDING.'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Text(
            '1. Criar modelo na Meta',
            style: TextStyle(
              color: widget.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Crie modelos oficiais da Meta (Cloud API). Após criar, eles aparecem na lista para disparo quando forem aprovados.',
            style: TextStyle(color: widget.mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
        ] else ...[
          Text(
            'Nome (snake_case), corpo BODY, categoria e idioma oficiais da Meta.',
            style: TextStyle(color: widget.mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _nameCtrl,
          style: TextStyle(color: widget.textColor, fontSize: 13),
          decoration: _inputDecoration('Nome do modelo (snake_case)'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bodyCtrl,
          maxLines: 3,
          style: TextStyle(color: widget.textColor, fontSize: 13),
          decoration: _inputDecoration('Corpo da mensagem (BODY)'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _category,
                dropdownColor: widget.cardColor,
                style: TextStyle(color: widget.textColor, fontSize: 13),
                decoration: _inputDecoration('Categoria'),
                items: const [
                  DropdownMenuItem(value: 'UTILITY', child: Text('UTILITY')),
                  DropdownMenuItem(value: 'MARKETING', child: Text('MARKETING')),
                  DropdownMenuItem(
                    value: 'AUTHENTICATION',
                    child: Text('AUTHENTICATION'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _language,
                dropdownColor: widget.cardColor,
                style: TextStyle(color: widget.textColor, fontSize: 13),
                decoration: _inputDecoration('Idioma'),
                items: const [
                  DropdownMenuItem(value: 'pt_BR', child: Text('pt_BR')),
                  DropdownMenuItem(value: 'en_US', child: Text('en_US')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _creating ? null : _createTemplate,
            style: FilledButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: const Color(0xFF042F2E),
            ),
            child: Text(_creating ? 'Criando...' : 'Criar modelo'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
        if (widget.showExistingList) ...[
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_templates.isEmpty)
            Text(
              'Nenhum modelo encontrado.',
              style: TextStyle(color: widget.mutedColor, fontSize: 12),
            )
          else
            Column(
              children: _templates.map((item) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101726),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          color: widget.textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.language} | ${item.category} | ${item.status}',
                        style: TextStyle(color: widget.mutedColor, fontSize: 11),
                      ),
                      if (item.bodyText != null && item.bodyText!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.bodyText!,
                          style: TextStyle(color: widget.mutedColor, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor),
      ),
      child: content,
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: widget.mutedColor, fontSize: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: widget.borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: widget.accentColor),
      ),
    );
  }
}

class WhatsAppMetaConnectButton extends StatefulWidget {
  const WhatsAppMetaConnectButton({
    super.key,
    required this.tenantId,
    required this.onConnected,
    this.accentColor = const Color(0xFF22D3EE),
    this.label = 'Conectar via Meta (Coexistência)',
  });

  final String tenantId;
  final Future<void> Function() onConnected;
  final Color accentColor;
  final String label;

  @override
  State<WhatsAppMetaConnectButton> createState() => _WhatsAppMetaConnectButtonState();
}

class _WhatsAppMetaConnectButtonState extends State<WhatsAppMetaConnectButton> {
  bool _loading = false;

  Future<void> _connect() async {
    if (!isMetaEmbeddedSignupSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Embedded Signup disponivel apenas no admin web (Flutter Web).'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permita popups neste site. A Meta abrira uma janela para conectar o WhatsApp Business.',
          ),
          duration: Duration(seconds: 5),
        ),
      );

      final config = await whatsAppOnboardingService.getEmbeddedSignupConfig();
      final extras = config['extras'];
      final result = await launchMetaEmbeddedSignup(
        appId: config['app_id']?.toString() ?? '',
        configId: config['config_id']?.toString() ?? '',
        coexistence: true,
        extras: extras is Map ? Map<String, dynamic>.from(extras) : null,
      );
      if (result == null) {
        throw StateError('Cadastro cancelado ou incompleto');
      }

      final wabaId = result.wabaId;
      final phoneNumberId = result.phoneNumberId;
      if (wabaId == null || phoneNumberId == null) {
        throw StateError(
          'Meta nao retornou WABA/Phone Number ID. Complete o fluxo e informe os IDs manualmente se necessario.',
        );
      }

      final displayPhone = (result.displayPhoneNumber ?? '').trim();
      final resolvedPhone = displayPhone.isEmpty ? phoneNumberId : displayPhone;
      final exchange = await whatsAppOnboardingService.exchangeEmbeddedSignup(
        tenantId: widget.tenantId,
        code: result.code,
        wabaId: wabaId,
        phoneNumberId: phoneNumberId,
        displayPhoneNumber: resolvedPhone,
        displayName: 'WhatsApp $resolvedPhone',
        coexistence: true,
      );
      await widget.onConnected();
      if (!mounted) return;
      final phoneStatus = exchange['phone_status'];
      final status = phoneStatus is Map ? phoneStatus['status']?.toString() : null;
      final message = status == 'CONNECTED'
          ? 'WhatsApp conectado! Numero CONNECTED na Meta.'
          : 'Conta vinculada. Status: ${status ?? "aguardando verificacao"}. '
              'No celular: abra a mensagem da Meta, toque Conectar e cole o codigo.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (err) {
      if (!mounted) return;
      final text = '$err';
      final friendly = text.contains('WABA/Phone Number ID')
          ? 'Meta nao enviou os IDs. Complete o codigo de verificacao no celular e tente de novo.'
          : (text.contains('cancelado') || text.contains('incompleto'))
              ? 'Popup bloqueado ou fluxo cancelado. Permita popups e use a URL https do tunnel.'
              : text.contains('META_APP_SECRET')
                  ? 'Configure META_APP_SECRET no backend e reinicie o Docker.'
                  : text.contains('422')
                      ? 'A Meta concluiu o cadastro, mas o painel rejeitou o payload (numero de exibicao vazio). Tente conectar de novo.'
                      : text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao conectar: $friendly')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _connect,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link_rounded, size: 16),
      label: Text(_loading ? 'Conectando...' : widget.label),
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.accentColor,
        side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
      ),
    );
  }
}
