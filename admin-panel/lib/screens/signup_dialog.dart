// ============================================================================
// SignupDialog - Dialog consultivo multi-step compartilhado entre Landing e Login.
// Coleta dados de empresa, objetivo de WhatsApp e contato para gerar lead.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_client.dart';
import '../services/lead_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/public_surface.dart';

class SignupDialog extends StatefulWidget {
  const SignupDialog({super.key});

  @override
  State<SignupDialog> createState() => _SignupDialogState();
}

class _SignupDialogState extends State<SignupDialog> {
  static const int _totalSteps = 3;

  int _step = 0;
  bool _submitting = false;
  bool _submitted = false;
  String? _errorMessage;
  String? _fieldErrorKey;

  final _company = TextEditingController();
  final _segment = TextEditingController();
  final _objective = TextEditingController();
  final _currentTools = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _whatsapp = TextEditingController();

  static const List<String> _segments = [
    'Alimentação e bebidas',
    'E-commerce e varejo',
    'Saúde e bem-estar',
    'Educação e cursos',
    'Serviços profissionais',
    'Imobiliário',
    'Estética e beleza',
    'Indústria / B2B',
    'Tecnologia / SaaS',
    'Outro',
  ];

  static const List<String> _volumeOptions = [
    'Até 500 mensagens / mês',
    '500 a 2.000',
    '2.000 a 5.000',
    '5.000 a 20.000',
    'Mais de 20.000',
    'Ainda não sei',
  ];

  static const List<String> _bestTimes = [
    'Manhã (08h-12h)',
    'Tarde (12h-18h)',
    'Noite (18h-21h)',
    'Qualquer horário comercial',
  ];

  String? _selectedSegment;
  String? _selectedVolume;
  String? _selectedBestTime;

  @override
  void dispose() {
    _company.dispose();
    _segment.dispose();
    _objective.dispose();
    _currentTools.dispose();
    _name.dispose();
    _email.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: _submitted ? _buildSuccess(context) : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Etapa ${_step + 1} de $_totalSteps',
                  style: GoogleFonts.manrope(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StepProgress(step: _step, total: _totalSteps),
          const SizedBox(height: 18),
          Text(
            _titleForStep(),
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _subtitleForStep(),
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          ..._fieldsForStep(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            PublicErrorBanner(text: _errorMessage!),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: _submitting ? null : () => setState(() => _step--),
                  child: Text(
                    'Voltar',
                    style: GoogleFonts.manrope(color: AppColors.textMuted),
                  ),
                ),
              const Spacer(),
              PublicPrimaryButton(
                label: _submitting
                    ? 'Enviando...'
                    : (_step == _totalSteps - 1 ? 'Enviar para a equipe' : 'Continuar'),
                icon: _submitting
                    ? null
                    : (_step == _totalSteps - 1
                        ? Icons.send_rounded
                        : Icons.arrow_forward_rounded),
                onTap: _submitting ? null : _handlePrimary,
                loading: _submitting,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Ao enviar, você concorda em receber um contato comercial da Operada.',
            style: GoogleFonts.manrope(
              color: AppColors.textSoft,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.primarySoft, size: 30),
          ),
          const SizedBox(height: 22),
          Text(
            'Recebemos suas informações',
            style: GoogleFonts.manrope(
              color: AppColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nosso time já está montando uma proposta personalizada para ${_company.text.trim().isNotEmpty ? _company.text.trim() : 'sua empresa'}. '
            'Em até 1 dia útil você receberá um contato no WhatsApp e e-mail informados.',
            style: GoogleFonts.manrope(
              color: AppColors.textMuted,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded, color: AppColors.accentBlue, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preparamos uma automação base sob medida para o seu segmento. '
                    'Assim que conversarmos, você já entra com tudo pronto para operar.',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: PublicPrimaryButton(
              label: 'Fechar',
              icon: Icons.check_circle_outline_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePrimary() {
    setState(() {
      _errorMessage = null;
      _fieldErrorKey = null;
    });
    final validationError = _validateStep();
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError.message;
        _fieldErrorKey = validationError.field;
      });
      return;
    }
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _submitLead();
    }
  }

  ({String field, String message})? _validateStep() {
    if (_step == 0) {
      if (_company.text.trim().length < 2) {
        return (field: 'company', message: 'Informe o nome da empresa.');
      }
      final segmentValue = _selectedSegment ?? _segment.text.trim();
      if (segmentValue.isEmpty) {
        return (field: 'segment', message: 'Selecione um segmento.');
      }
    }
    if (_step == 1) {
      if (_objective.text.trim().length < 5) {
        return (
          field: 'objective',
          message: 'Conte rapidamente o que você quer automatizar no WhatsApp.',
        );
      }
    }
    if (_step == 2) {
      if (_name.text.trim().length < 2) {
        return (field: 'name', message: 'Informe seu nome.');
      }
      final email = _email.text.trim();
      final emailRegex = RegExp(r'^[\w.\-+]+@[\w\-]+\.[\w.\-]+$');
      if (!emailRegex.hasMatch(email)) {
        return (field: 'email', message: 'Informe um e-mail corporativo válido.');
      }
      final digits = _whatsapp.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 10) {
        return (field: 'whatsapp', message: 'Informe um WhatsApp com DDD válido.');
      }
    }
    return null;
  }

  Future<void> _submitLead() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final segmentValue = (_selectedSegment ?? '').trim().isNotEmpty
          ? _selectedSegment!.trim()
          : _segment.text.trim();
      await leadService.submitPublicLead(
        name: _name.text,
        company: _company.text,
        segment: segmentValue,
        email: _email.text,
        whatsapp: _whatsapp.text,
        objective: _objective.text,
        monthlyVolume: _selectedVolume,
        currentTools: _currentTools.text,
        bestContactTime: _selectedBestTime,
        source: 'landing',
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
      });
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrorKey = null;
        _errorMessage = _friendlyError(exc.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrorKey = null;
        _errorMessage = 'Não foi possível enviar agora. Tente novamente em instantes.';
      });
    }
  }

  String _friendlyError(String raw) {
    if (raw.isEmpty) return 'Erro inesperado ao enviar o cadastro.';
    try {
      final match = RegExp('"detail":"([^"]+)"').firstMatch(raw);
      if (match != null) return match.group(1)!;
    } catch (_) {}
    return 'Não foi possível enviar agora. Verifique os dados e tente novamente.';
  }

  String _titleForStep() {
    return [
      'Vamos conhecer sua empresa',
      'Como será seu atendimento no WhatsApp?',
      'Como podemos falar com você?',
    ][_step];
  }

  String _subtitleForStep() {
    return [
      'Essas informações ajudam o nosso time a desenhar a melhor proposta para o seu negócio.',
      'Quanto mais detalhe, mais personalizada fica a sua automação inicial.',
      'Vamos te chamar no WhatsApp e e-mail com uma proposta sob medida.',
    ][_step];
  }

  List<Widget> _fieldsForStep() {
    if (_step == 0) {
      return [
        _DialogField(
          label: 'Nome da empresa',
          hint: 'Ex: Bella Pizza, Studio Mariana, Casa & Estilo...',
          controller: _company,
          error: _fieldErrorKey == 'company' ? _errorMessage : null,
        ),
        const SizedBox(height: 14),
        _DialogDropdown(
          label: 'Segmento',
          hint: 'Selecione o que melhor descreve o seu negócio',
          value: _selectedSegment,
          options: _segments,
          error: _fieldErrorKey == 'segment' ? _errorMessage : null,
          onChanged: (value) => setState(() {
            _selectedSegment = value;
            if (value != 'Outro') {
              _segment.text = value ?? '';
            } else {
              _segment.clear();
            }
          }),
        ),
        if (_selectedSegment == 'Outro') ...[
          const SizedBox(height: 12),
          _DialogField(
            label: 'Conte qual é o seu segmento',
            hint: 'Ex: Estúdio de tatuagem premium',
            controller: _segment,
          ),
        ],
      ];
    }
    if (_step == 1) {
      return [
        _DialogField(
          label: 'O que você pretende fornecer pelo WhatsApp?',
          hint:
              'Ex: atendimento ao cliente, cardápio digital, catálogo de produtos, agendamento de horários, suporte pós-venda, qualificação de leads...',
          controller: _objective,
          maxLines: 4,
          error: _fieldErrorKey == 'objective' ? _errorMessage : null,
        ),
        const SizedBox(height: 14),
        _DialogDropdown(
          label: 'Volume mensal estimado de mensagens',
          hint: 'Selecione uma faixa aproximada',
          value: _selectedVolume,
          options: _volumeOptions,
          onChanged: (value) => setState(() => _selectedVolume = value),
        ),
        const SizedBox(height: 14),
        _DialogField(
          label: 'Quais ferramentas você usa hoje? (opcional)',
          hint: 'Ex: WhatsApp Business + planilha, Zendesk, RD Station, nenhum sistema...',
          controller: _currentTools,
          maxLines: 2,
        ),
      ];
    }
    return [
      _DialogField(
        label: 'Seu nome',
        hint: 'Como devemos te chamar',
        controller: _name,
        error: _fieldErrorKey == 'name' ? _errorMessage : null,
      ),
      const SizedBox(height: 14),
      _DialogField(
        label: 'E-mail corporativo',
        hint: 'voce@empresa.com',
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        error: _fieldErrorKey == 'email' ? _errorMessage : null,
      ),
      const SizedBox(height: 14),
      _DialogField(
        label: 'WhatsApp com DDD',
        hint: '(11) 9 9999-9999',
        controller: _whatsapp,
        keyboardType: TextInputType.phone,
        error: _fieldErrorKey == 'whatsapp' ? _errorMessage : null,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
          _BrazilianPhoneFormatter(),
        ],
      ),
      const SizedBox(height: 14),
      _DialogDropdown(
        label: 'Melhor horário para contato',
        hint: 'Selecione o horário preferido',
        value: _selectedBestTime,
        options: _bestTimes,
        onChanged: (value) => setState(() => _selectedBestTime = value),
      ),
    ];
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / total;
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2C),
        borderRadius: BorderRadius.circular(999),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: kPublicCtaGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrazilianPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 11; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7 && digits.length == 11) buffer.write('-');
      if (i == 6 && digits.length == 10) buffer.write('-');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.error,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? AppColors.danger : Colors.white.withValues(alpha: 0.08),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.manrope(color: AppColors.textSoft, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF080A12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.danger : AppColors.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _DialogDropdown extends StatelessWidget {
  const _DialogDropdown({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    this.error,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF080A12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (error != null && error!.isNotEmpty)
                  ? AppColors.danger
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF11141C),
              iconEnabledColor: AppColors.textMuted,
              hint: Text(
                hint,
                style: GoogleFonts.manrope(color: AppColors.textSoft, fontSize: 14),
              ),
              style: GoogleFonts.manrope(color: AppColors.text, fontSize: 14),
              borderRadius: BorderRadius.circular(12),
              items: options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ),
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: GoogleFonts.manrope(color: AppColors.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
