import 'package:flutter/material.dart';

import '../models/whatsapp_account.dart';
import '../services/whatsapp_template_service.dart';
import '../theme/app_tokens.dart';
import '../utils/wa_template_rules.dart';
import 'wa_template_text_field.dart';
import 'whatsapp_template_phone_preview.dart';

/// Dialog em 4 etapas: Informações, Conteúdo, Botões, Revisão + preview.
Future<void> showTemplateWizardDialog({
  required BuildContext context,
  required String tenantId,
  required List<WhatsAppAccountModel> accounts,
  String? accountKey,
  VoidCallback? onCreated,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TemplateWizardDialog(
      tenantId: tenantId,
      accounts: accounts,
      initialAccountKey: accountKey,
      onCreated: onCreated,
    ),
  );
}

class _TemplateWizardDialog extends StatefulWidget {
  const _TemplateWizardDialog({
    required this.tenantId,
    required this.accounts,
    this.initialAccountKey,
    this.onCreated,
  });

  final String tenantId;
  final List<WhatsAppAccountModel> accounts;
  final String? initialAccountKey;
  final VoidCallback? onCreated;

  @override
  State<_TemplateWizardDialog> createState() => _TemplateWizardDialogState();
}

class _TemplateWizardDialogState extends State<_TemplateWizardDialog> {
  int _step = 0;
  bool _saving = false;
  String? _error;
  String? _accountKey;
  String _category = 'UTILITY';
  String _language = 'pt_BR';
  String _headerFormat = 'NONE';
  final _nameCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  final _headerTextCtrl = TextEditingController();
  final _examplesCtrl = TextEditingController();
  final List<_WizardButton> _buttons = [];
  String? _headerError;
  String? _bodyError;
  String? _footerError;
  String? _examplesError;
  final List<String?> _buttonErrors = [];

  static const _placeholderVar = '⟨exemplo⟩';

  @override
  void initState() {
    super.initState();
    _accountKey = widget.initialAccountKey ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.accountKey : null);
    for (final c in [
      _nameCtrl,
      _bodyCtrl,
      _footerCtrl,
      _headerTextCtrl,
      _examplesCtrl,
    ]) {
      c.addListener(_scheduleRefresh);
    }
  }

  void _scheduleRefresh() {
    _validateContentFields(showAll: false);
    setState(() {});
  }

  void _validateContentFields({required bool showAll}) {
    _headerError = _headerFormat == 'TEXT'
        ? WaTemplateRules.validateHeader(_headerTextCtrl.text)
        : null;
    _bodyError = WaTemplateRules.validateBody(_bodyCtrl.text, examples: _varSamples);
    _footerError = WaTemplateRules.validateFooter(_footerCtrl.text);
    _examplesError = null;
    final vars = WaTemplateRules.variables(_bodyCtrl.text);
    if (vars.isNotEmpty && _varSamples.isEmpty) {
      _examplesError = 'Informe exemplos separados por |.';
    }
    _buttonErrors
      ..clear()
      ..addAll(
        _buttons.map((b) => WaTemplateRules.validateButtonLabel(b.text, field: 'Texto do botão')),
      );
    if (!showAll && _step != 1) {
      if (_step != 2) {
        _buttonErrors.clear();
      }
    }
  }

  bool _validateCurrentStep() {
    if (_step == 1) {
      _validateContentFields(showAll: true);
      return _headerError == null &&
          _bodyError == null &&
          _footerError == null &&
          _examplesError == null;
    }
    if (_step == 2 && _category != 'AUTHENTICATION') {
      _validateContentFields(showAll: true);
      final btnOk = _buttonErrors.every((e) => e == null);
      for (var i = 0; i < _buttons.length; i++) {
        final b = _buttons[i];
        if (b.type == 'PHONE_NUMBER' && (b.phone ?? '').trim().isEmpty) {
          while (_buttonErrors.length <= i) _buttonErrors.add(null);
          _buttonErrors[i] = 'Informe telefone E.164.';
        }
        if (b.type == 'URL' && (b.url ?? '').trim().isEmpty) {
          while (_buttonErrors.length <= i) _buttonErrors.add(null);
          _buttonErrors[i] = 'Informe URL.';
        }
      }
      return btnOk && _buttonErrors.every((e) => e == null);
    }
  if (_step == 3) {
      _validateContentFields(showAll: true);
      return _headerError == null && _bodyError == null && _footerError == null;
    }
    return true;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _bodyCtrl,
      _footerCtrl,
      _headerTextCtrl,
      _examplesCtrl,
    ]) {
      c.removeListener(_scheduleRefresh);
      c.dispose();
    }
    for (final b in _buttons) {
      b.dispose();
    }
    super.dispose();
  }

  List<String> get _varSamples {
    final raw = _examplesCtrl.text.trim();
    if (raw.isEmpty) return [];
    return raw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  String _substituteVars(String text) {
    final samples = _varSamples;
    var i = 0;
    return text.replaceAllMapped(RegExp(r'\{\{(\d+|[a-zA-Z_][a-zA-Z0-9_]*)\}\}'), (m) {
      if (i < samples.length) return samples[i++];
      return _placeholderVar;
    });
  }

  String get _previewBody => _substituteVars(_bodyCtrl.text);

  String get _businessName {
    WhatsAppAccountModel? acc;
    for (final a in widget.accounts) {
      if (a.accountKey == _accountKey) {
        acc = a;
        break;
      }
    }
    if (acc == null) return 'Sua empresa';
    if (acc.displayName.isNotEmpty) return acc.displayName;
    if (acc.displayPhoneNumber.isNotEmpty) return acc.displayPhoneNumber;
    return acc.accountKey;
  }

  static List<String> allowedButtonTypes(String category) {
    switch (category) {
      case 'MARKETING':
        return const ['QUICK_REPLY', 'PHONE_NUMBER', 'URL', 'COPY_CODE'];
      case 'AUTHENTICATION':
        return const [];
      default:
        return const ['QUICK_REPLY', 'PHONE_NUMBER', 'URL'];
    }
  }

  Future<void> _onCategoryChanged(String? v) async {
    final next = v ?? 'UTILITY';
    if (next == _category) return;
    final allowed = allowedButtonTypes(next);
    final bad = _buttons.where((b) => !allowed.contains(b.type)).toList();
    if (bad.isNotEmpty) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Categoria incompatível'),
          content: Text(
            'Ao mudar para $next, ${bad.length} botão(ões) serão removidos '
            '(tipos não permitidos nesta categoria).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (drop != true || !mounted) return;
      setState(() {
        _buttons.removeWhere((b) => !allowed.contains(b.type));
        _category = next;
      });
      return;
    }
    setState(() => _category = next);
  }

  String _formatSubmitError(Object err) {
    final raw = err.toString().replaceFirst('ApiException(400): ', '').replaceFirst('Exception: ', '');
    if (raw.contains('(#100)') || raw.contains('erro #100')) {
      return raw;
    }
    return raw;
  }

  TemplatePhonePreviewData _previewData() {
    final previewButtons = <TemplatePreviewButton>[];
    for (final b in _buttons) {
      if (b.text.trim().isEmpty && b.type != 'COPY_CODE') continue;
      var label = b.text.trim();
      if (b.type == 'COPY_CODE') {
        label = label.isNotEmpty ? label : 'Copiar código';
        final code = b.copyCode?.trim();
        if (code != null && code.isNotEmpty) label = '$label · $code';
      }
      previewButtons.add(TemplatePreviewButton(type: b.type, label: label));
    }
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return TemplatePhonePreviewData(
      businessName: _businessName,
      headerFormat: _headerFormat,
      headerText: _substituteVars(_headerTextCtrl.text),
      bodyResolved: _previewBody,
      footerText: _footerCtrl.text,
      buttons: previewButtons,
      timeLabel: time,
    );
  }

  Future<void> _submit() async {
    if (!_validateCurrentStep()) {
      setState(() {});
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? header;
      if (_headerFormat == 'TEXT' && _headerTextCtrl.text.trim().isNotEmpty) {
        header = {'format': 'TEXT', 'text': _headerTextCtrl.text.trim()};
      }
      final allowed = allowedButtonTypes(_category);
      final buttons = _buttons
          .where((b) => b.text.trim().isNotEmpty && allowed.contains(b.type))
          .take(3)
          .map((b) {
            final map = <String, dynamic>{
              'type': b.type,
              'text': b.text.trim(),
            };
            if (b.type == 'PHONE_NUMBER' && b.phone != null && b.phone!.trim().isNotEmpty) {
              map['phone_number'] = b.phone!.trim();
            }
            if (b.type == 'URL' && b.url != null && b.url!.trim().isNotEmpty) {
              map['url'] = b.url!.trim();
            }
            if (b.type == 'COPY_CODE' && b.copyCode != null && b.copyCode!.trim().isNotEmpty) {
              map['example'] = [b.copyCode!.trim()];
            }
            return map;
          })
          .toList();
      await whatsAppTemplateService.createTemplate(
        tenantId: widget.tenantId,
        name: _nameCtrl.text.trim(),
        language: _language,
        category: _category,
        bodyText: _bodyCtrl.text.trim(),
        accountKey: _accountKey,
        footerText: _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text.trim(),
        header: header,
        buttons: buttons.isEmpty ? null : buttons,
        bodyExamples: _varSamples.isEmpty ? null : _varSamples,
      );
      if (!mounted) return;
      widget.onCreated?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modelo enviado à Meta (PENDING).')),
      );
    } catch (err) {
      setState(() => _error = _formatSubmitError(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final view = MediaQuery.sizeOf(context);
    final maxDialogH = (view.height - 40).clamp(480.0, 720.0);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 1180 : 560, maxHeight: maxDialogH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Novo template WhatsApp',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StepIndicator(step: _step),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: _buildEditor(compact: false)),
                          const SizedBox(width: 12),
                          Expanded(flex: 9, child: _buildPreviewPane()),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final previewH =
                              (constraints.maxHeight * 0.48).clamp(240.0, WhatsAppTemplatePhonePreview.designHeight * 1.05);
                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: previewH, child: _buildPreviewPane(maxScale: 1.05)),
                                const SizedBox(height: 16),
                                ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraints.maxHeight * 0.45),
                                  child: _buildEditor(compact: true),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: const Text('Voltar'),
                    ),
                  const Spacer(),
                  if (_step < 3)
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () {
                              if (!_validateCurrentStep()) {
                                setState(() {});
                                return;
                              }
                              setState(() => _step++);
                            },
                      child: const Text('Continuar'),
                    )
                  else
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enviar à Meta'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openExpandedPreview() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Expanded(
                child: WhatsAppTemplatePhonePreviewFrame(
                  data: _previewData(),
                  minScale: 0.9,
                  maxScale: 1.28,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPane({double maxScale = 1.18}) {
    return WhatsAppTemplatePhonePreviewFrame(
      data: _previewData(),
      maxScale: maxScale,
      onExpand: _openExpandedPreview,
    );
  }

  Widget _buildEditor({required bool compact}) {
    final listView = (List<Widget> children) => ListView(
          shrinkWrap: compact,
          physics: compact ? const NeverScrollableScrollPhysics() : null,
          children: children,
        );
    switch (_step) {
      case 0:
        return listView([
            DropdownButtonFormField<String>(
              value: _accountKey,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Conta WhatsApp (WABA)'),
              items: widget.accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.accountKey,
                      child: Text(
                        a.displayPhoneNumber.isNotEmpty
                            ? '${a.displayPhoneNumber}\nWABA ${a.accountKey}'
                            : 'WABA ${a.accountKey}',
                        style: const TextStyle(height: 1.3),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _accountKey = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nome (snake_case)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _language,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Idioma'),
              items: const [
                DropdownMenuItem(value: 'pt_BR', child: Text('Português (BR)')),
                DropdownMenuItem(value: 'en_US', child: Text('English (US)')),
              ],
              onChanged: (v) => setState(() => _language = v ?? 'pt_BR'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Categoria Meta'),
              items: const [
                DropdownMenuItem(value: 'MARKETING', child: Text('MARKETING')),
                DropdownMenuItem(value: 'UTILITY', child: Text('UTILITY')),
                DropdownMenuItem(value: 'AUTHENTICATION', child: Text('AUTHENTICATION')),
              ],
              onChanged: _saving ? null : _onCategoryChanged,
            ),
        ]);
      case 1:
        return listView([
            DropdownButtonFormField<String>(
              value: _headerFormat,
              dropdownColor: AppColors.surfaceAlt,
              decoration: const InputDecoration(labelText: 'Cabeçalho'),
              items: const [
                DropdownMenuItem(value: 'NONE', child: Text('Sem cabeçalho')),
                DropdownMenuItem(value: 'TEXT', child: Text('Texto')),
              ],
              onChanged: (v) => setState(() => _headerFormat = v ?? 'NONE'),
            ),
            if (_headerFormat == 'TEXT') ...[
              const SizedBox(height: 8),
              WaTemplateTextField(
                controller: _headerTextCtrl,
                mode: WaTemplateFieldMode.headerPlain,
                maxLength: 60,
                labelText: 'Texto do cabeçalho',
                helperText: 'Texto simples, até 1 variável, sem emoji.',
                errorText: _headerError,
              ),
            ],
            const SizedBox(height: 12),
            WaTemplateTextField(
              controller: _bodyCtrl,
              mode: WaTemplateFieldMode.body,
              minLines: 4,
              maxLines: 8,
              maxLength: 1024,
              labelText: 'Corpo',
              helperText: 'Variáveis {{1}} ou {{nome}} — exemplos abaixo separados por |',
              errorText: _bodyError,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _examplesCtrl,
              decoration: InputDecoration(
                labelText: 'Exemplos para aprovação (| entre valores)',
                errorText: _examplesError,
              ),
            ),
            const SizedBox(height: 12),
            WaTemplateTextField(
              controller: _footerCtrl,
              mode: WaTemplateFieldMode.footerPlain,
              maxLength: 60,
              labelText: 'Rodapé (opcional)',
              helperText: 'Texto simples, sem variáveis nem emoji.',
              errorText: _footerError,
            ),
        ]);
      case 2:
        if (_category == 'AUTHENTICATION') {
          return listView(const [
              Icon(Icons.lock_outline_rounded, color: AppColors.textSoft, size: 40),
              SizedBox(height: 12),
              Text(
                'Templates AUTHENTICATION (OTP) não usam botões de chamada neste assistente. '
                'O corpo e a categoria serão enviados conforme as regras da Meta.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
          ]);
        }
        return listView([
            ..._buttons.asMap().entries.map((e) => _ButtonRow(
                  category: _category,
                  data: e.value,
                  errorText: e.key < _buttonErrors.length ? _buttonErrors[e.key] : null,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() {
                    e.value.dispose();
                    _buttons.remove(e.value);
                  }),
                )),
            if (_buttons.length < 3)
              TextButton.icon(
                onPressed: () => setState(() => _buttons.add(_WizardButton())),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar botão (máx. 3)'),
              ),
        ]);
      default:
        return listView([
            Text('Conta: $_accountKey', style: const TextStyle(color: AppColors.textMuted)),
            Text('Nome: ${_nameCtrl.text}', style: const TextStyle(color: AppColors.text)),
            Text('Categoria: $_category / $_language'),
            const SizedBox(height: 8),
            const Text(
              'Confira o template no preview ao lado antes de enviar.',
              style: TextStyle(color: AppColors.textSoft, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_headerFormat == 'TEXT' && _headerTextCtrl.text.isNotEmpty)
              Text('Cabeçalho: ${_headerTextCtrl.text}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(_bodyCtrl.text, style: const TextStyle(color: AppColors.text)),
            if (_footerCtrl.text.isNotEmpty)
              Text('Rodapé: ${_footerCtrl.text}', style: const TextStyle(fontSize: 12)),
            if (_buttons.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Botões:', style: TextStyle(fontWeight: FontWeight.w600)),
              ..._buttons.map(
                (b) => Text('• ${b.type}: ${b.text}', style: const TextStyle(fontSize: 12)),
              ),
            ],
        ]);
    }
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;
  static const _labels = ['Informações', 'Conteúdo', 'Botões', 'Revisão'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length, (i) {
        final active = i <= step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    color: active ? AppColors.primary : AppColors.textSoft,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _WizardButton {
  String type = 'QUICK_REPLY';
  String text = '';
  String? phone;
  String? url;
  String? copyCode;

  late final TextEditingController textCtrl = TextEditingController();
  late final TextEditingController phoneCtrl = TextEditingController();
  late final TextEditingController urlCtrl = TextEditingController();
  late final TextEditingController copyCodeCtrl = TextEditingController();

  void dispose() {
    textCtrl.dispose();
    phoneCtrl.dispose();
    urlCtrl.dispose();
    copyCodeCtrl.dispose();
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.category,
    required this.data,
    required this.onChanged,
    required this.onRemove,
    this.errorText,
  });

  final String category;
  final _WizardButton data;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final types = _TemplateWizardDialogState.allowedButtonTypes(category);
    final currentType = types.contains(data.type) ? data.type : types.first;
    if (currentType != data.type) {
      data.type = currentType;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surfaceAlt,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: currentType,
              dropdownColor: AppColors.surfaceAlt,
              items: [
                for (final t in types)
                  DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
              ],
              onChanged: (v) {
                data.type = v ?? 'QUICK_REPLY';
                onChanged();
              },
            ),
            TextField(
              controller: data.textCtrl,
              maxLength: 25,
              decoration: InputDecoration(
                labelText: data.type == 'COPY_CODE' ? 'Rótulo do botão (ex.: Copiar cupom)' : 'Texto do botão',
                errorText: errorText,
              ),
              onChanged: (v) {
                data.text = v;
                onChanged();
              },
            ),
            if (data.type == 'PHONE_NUMBER')
              TextField(
                controller: data.phoneCtrl,
                decoration: const InputDecoration(labelText: 'Telefone E.164'),
                onChanged: (v) {
                  data.phone = v;
                  onChanged();
                },
              ),
            if (data.type == 'URL')
              TextField(
                controller: data.urlCtrl,
                decoration: const InputDecoration(labelText: 'URL'),
                onChanged: (v) {
                  data.url = v;
                  onChanged();
                },
              ),
            if (data.type == 'COPY_CODE')
              TextField(
                controller: data.copyCodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código do cupom (exemplo para a Meta)',
                  helperText: 'Não é o texto do botão — é o valor que o usuário copia.',
                ),
                onChanged: (v) {
                  data.copyCode = v;
                  onChanged();
                },
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'PHONE_NUMBER':
        return 'Telefone';
      case 'URL':
        return 'URL';
      case 'COPY_CODE':
        return 'Copiar cupom (MARKETING)';
      default:
        return 'Resposta rápida';
    }
  }
}