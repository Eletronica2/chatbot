import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/whatsapp_onboarding_service.dart';
import '../theme/app_tokens.dart';
import 'whatsapp_meta_panels.dart';

Future<void> showCoexistenceWizard({
  required BuildContext context,
  required String tenantId,
  required Future<void> Function() onConnected,
  Color accentColor = AppColors.primary,
  int initialStep = 0,
}) {
  final size = MediaQuery.sizeOf(context);
  final horizontal = size.width < 500 ? 12.0 : 16.0;
  final vertical = size.height < 700 ? 12.0 : 24.0;
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: size.height - (vertical * 2),
        ),
        child: CoexistenceWizard(
          tenantId: tenantId,
          onConnected: onConnected,
          accentColor: accentColor,
          initialStep: initialStep,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
}

class CoexistenceWizard extends StatefulWidget {
  const CoexistenceWizard({
    super.key,
    required this.tenantId,
    required this.onConnected,
    required this.onClose,
    this.accentColor = AppColors.primary,
    this.initialStep = 0,
  });

  final String tenantId;
  final Future<void> Function() onConnected;
  final VoidCallback onClose;
  final Color accentColor;
  final int initialStep;

  @override
  State<CoexistenceWizard> createState() => _CoexistenceWizardState();
}

class _CoexistenceWizardState extends State<CoexistenceWizard> {
  late int _step;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _preflight = <String, dynamic>{};
  bool _backendOk = false;
  final _webhookUrlCtrl = TextEditingController();

  bool get _isHttps {
    if (!kIsWeb) return false;
    return Uri.base.scheme == 'https';
  }

  String get _adminHost => kIsWeb ? Uri.base.host : 'seu-dominio.trycloudflare.com';

  String get _adminOrigin => kIsWeb ? Uri.base.origin : 'https://$_adminHost';

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.clamp(0, 2);
    _loadPreflight();
  }

  @override
  void dispose() {
    _webhookUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreflight() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final health = await apiClient.get('/health');
      _backendOk = health is Map && (health['status'] == 'healthy' || health['status'] == 'ok');
      _preflight = await whatsAppOnboardingService.getEmbeddedSignupPreflight();
      if (_webhookUrlCtrl.text.isEmpty) {
        _webhookUrlCtrl.text = 'https://SEU-TUNNEL-GATEWAY.trycloudflare.com/webhook';
      }
    } catch (err) {
      _error = '$err';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir: $url')),
      );
    }
  }

  Map<String, dynamic> get _metaLinks {
    final links = _preflight['meta_links'];
    if (links is Map) {
      return Map<String, dynamic>.from(links);
    }
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Assistente de coexistência',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Siga as etapas na ordem. Use os botões para abrir as telas da Meta e copiar os valores.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          _buildStepIndicator(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : _buildStepContent(),
            ),
          ),
          const SizedBox(height: 12),
          _buildNavButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const labels = ['Ambiente', 'Meta', 'Conectar'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index == _step;
        final done = index < _step;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done || active ? widget.accentColor : AppColors.surfaceSoft,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: done || active ? Colors.black : AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? AppColors.text : AppColors.textMuted,
                  ),
                ),
              ),
              if (index < labels.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textSoft),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          const SizedBox(height: 10),
          TextButton(onPressed: _loadPreflight, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStepEnvironment();
      case 1:
        return _buildStepMeta();
      default:
        return _buildStepConnect();
    }
  }

  Widget _buildStepEnvironment() {
    final secretOk = _preflight['app_secret_configured'] == true;
    final configId = _preflight['config_id']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _checkRow('Backend online', _backendOk),
        _checkRow('META_APP_SECRET configurado', secretOk),
        _checkRow('Configuration ID ($configId)', configId.isNotEmpty),
        _checkRow('Admin em HTTPS (obrigatório Meta)', _isHttps),
        if (!_isHttps) ...[
          const SizedBox(height: 12),
          const Text(
            'Abra o painel pela URL https://....trycloudflare.com (não localhost). '
            'Rode: scripts/start-coexistence-session.ps1',
            style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.4),
          ),
        ],
        if (!secretOk) ...[
          const SizedBox(height: 12),
          const Text(
            'Cole META_APP_SECRET em backend-api/.env e reinicie: docker compose up -d backend-api',
            style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _buildStepMeta() {
    final verifyToken = _preflight['verify_token']?.toString() ?? '';
    final verifyPreview = verifyToken.isEmpty
        ? '(não configurado)'
        : (verifyToken.length <= 8
            ? '••••••••'
            : '${verifyToken.substring(0, 4)}…${verifyToken.substring(verifyToken.length - 4)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Abra cada tela na Meta e use Copiar para colar os valores. '
          'O token de verificação é necessário no webhook — copie sob demanda.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        _metaLinkRow(
          'App Domains + JS SDK',
          _metaLinks['app_domains']?.toString(),
          'Domínio (sem https://)',
          _adminHost,
        ),
        const SizedBox(height: 10),
        _metaLinkRow(
          'Facebook Login for Business',
          _metaLinks['fb_login_for_business']?.toString(),
          'Valid OAuth Redirect URI',
          '$_adminOrigin/',
        ),
        const SizedBox(height: 10),
        _metaLinkRow(
          'WhatsApp Webhook',
          _metaLinks['whatsapp_webhook']?.toString(),
          'Verify token',
          verifyToken.isEmpty ? verifyPreview : verifyToken,
          displayValue: verifyPreview,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _webhookUrlCtrl,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Callback URL (webhook gateway)',
            hintText: 'https://seu-tunnel.trycloudflare.com/webhook',
            border: OutlineInputBorder(),
            helperText: 'URL pública HTTPS do gateway + /webhook',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _copy('Webhook URL', _webhookUrlCtrl.text.trim()),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar webhook URL'),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fluxo de coexistência (Meta 2026):',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '1. Clique em Conectar e permita o popup da Meta no navegador\n'
                '2. No popup: escolha conectar a conta existente do WhatsApp Business\n'
                '3. Informe o número Business e copie o código de verificação\n'
                '4. No celular: mensagem da Meta → Conectar → Confirmar → colar o código\n'
                '5. Aguarde a Meta concluir a verificação (pode levar alguns minutos)',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tela "Selecione os ativos" (Meta) — Avançar bloqueado?',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                'Não use o portfólio do app desenvolvedor: a Meta bloqueia '
                'o botão Avançar para Tech Providers.\n\n'
                'Combinação correta:\n'
                '• Portfólio empresarial → criar/selecionar o portfólio da sua empresa\n'
                '• Conta WhatsApp → conectar o app do WhatsApp Business '
                '(não “Criar conta” se o número já existe)\n\n'
                'Dica: prepare o portfólio em business.facebook.com antes, '
                'depois selecione-o no fluxo.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WhatsAppMetaConnectButton(
          tenantId: widget.tenantId,
          accentColor: widget.accentColor,
          onConnected: () async {
            await widget.onConnected();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Conta vinculada. Próximo passo: Templates WhatsApp → '
                    'aguarde APPROVED → enviar teste.',
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _checkRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _metaLinkRow(
    String title,
    String? metaUrl,
    String valueLabel,
    String value, {
    String? displayValue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$valueLabel: ${displayValue ?? value}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: value.isEmpty ? null : () => _copy(valueLabel, value),
                child: const Text('Copiar'),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _openUrl(metaUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Abrir na Meta'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Row(
      children: [
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step -= 1),
            child: const Text('Voltar'),
          ),
        const Spacer(),
        if (_step < 2)
          FilledButton(
            onPressed: _loading ? null : () => setState(() => _step += 1),
            style: FilledButton.styleFrom(backgroundColor: widget.accentColor),
            child: const Text('Próximo'),
          )
        else
          TextButton(onPressed: widget.onClose, child: const Text('Fechar')),
      ],
    );
  }
}
