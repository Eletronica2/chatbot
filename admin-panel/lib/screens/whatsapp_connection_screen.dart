import 'package:flutter/material.dart';

import '../models/whatsapp_account.dart';
import '../services/auth_service.dart';
import '../services/whatsapp_account_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/coexistence_wizard.dart';
import '../widgets/premium_ui.dart';
import '../widgets/whatsapp_meta_panels.dart';

/// WhatsApp do cliente final — conexão / coexistência (Fase 9).
/// Não confundir com Templates (Fase 8) nem com Clientes/superadmin (Fase 5).
class WhatsAppConnectionScreen extends StatefulWidget {
  const WhatsAppConnectionScreen({super.key});

  @override
  State<WhatsAppConnectionScreen> createState() =>
      _WhatsAppConnectionScreenState();
}

class _WhatsAppConnectionScreenState extends State<WhatsAppConnectionScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<WhatsAppAccountModel> _accounts = <WhatsAppAccountModel>[];

  String get _tenantId => authService.tenantId ?? '';

  List<WhatsAppAccountModel> get _activeAccounts =>
      _accounts.where((a) => a.status.toLowerCase() == 'active').toList();

  WhatsAppAccountModel? get _primaryAccount {
    final active = _activeAccounts;
    if (active.isEmpty) return null;
    for (final a in active) {
      if (a.isDefault) return a;
    }
    return active.first;
  }

  bool get _hasConnection => _primaryAccount != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_tenantId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Tenant não identificado. Faça login novamente.';
        _accounts = <WhatsAppAccountModel>[];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final accounts = await whatsAppAccountService.listAccounts(_tenantId);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWizard({int initialStep = 0}) async {
    if (_tenantId.isEmpty || _busy) return;
    await showCoexistenceWizard(
      context: context,
      tenantId: _tenantId,
      initialStep: initialStep,
      onConnected: _load,
    );
  }

  Future<void> _setDefault(WhatsAppAccountModel account) async {
    if (_busy || account.isDefault) return;
    setState(() => _busy = true);
    try {
      await whatsAppAccountService.updateAccount(
        tenantId: _tenantId,
        accountKey: account.accountKey,
        isDefault: true,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta marcada como principal.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $err')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(WhatsAppAccountModel account, String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await whatsAppAccountService.updateAccount(
        tenantId: _tenantId,
        accountKey: account.accountKey,
        status: status,
      );
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar status: $err')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Ativa';
      case 'inactive':
        return 'Inativa';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppColors.success;
      case 'inactive':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  return ListView(
                    padding: AppPageInsets.of(context),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!, onRetry: _load),
                        const SizedBox(height: 16),
                      ],
                      AppPageSwitcher(
                        pageKey: _hasConnection ? 'connected' : 'disconnected',
                        child: _hasConnection
                            ? _buildConnected(wide: wide)
                            : _buildDisconnected(),
                      ),
                      if (_accounts.length > 1) ...[
                        const SizedBox(height: 20),
                        _buildAccountsList(),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhatsApp',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Conecte o WhatsApp Business da sua empresa para atender pelo painel.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textMuted,
        ),
      ],
    );
  }

  Widget _buildDisconnected() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xxl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: AppRadius.lg,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(
              Icons.phonelink_setup_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Seu WhatsApp está pronto para atender?',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Conecte o número do WhatsApp Business via Meta. '
            'Assim o painel recebe mensagens e envia respostas e templates.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          const _RequirementRow(
            icon: Icons.business_rounded,
            text: 'Conta Meta Business e WhatsApp Business App',
          ),
          const _RequirementRow(
            icon: Icons.lock_outline_rounded,
            text: 'Painel aberto em HTTPS (exigência da Meta)',
          ),
          const _RequirementRow(
            icon: Icons.smartphone_rounded,
            text: 'Celular à mão para confirmar o código da Meta',
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _openWizard(),
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('Conectar WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
              WhatsAppMetaConnectButton(
                tenantId: _tenantId,
                accentColor: AppColors.primary,
                label: 'Abrir Meta agora',
                onConnected: _load,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnected({required bool wide}) {
    final account = _primaryAccount!;
    final statusColor = _statusColor(account.status);

    final hero = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xxl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      'Conta ${_statusLabel(account.status).toLowerCase()}',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (account.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: AppRadius.pill,
                  ),
                  child: const Text(
                    'Principal',
                    style: TextStyle(
                      color: AppColors.primarySoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            account.displayName.isNotEmpty
                ? account.displayName
                : 'WhatsApp Business',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            account.displayPhoneNumber.isNotEmpty
                ? account.displayPhoneNumber
                : 'Número não informado',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (account.hasAccessToken)
                const _InfoChip(
                  icon: Icons.verified_user_outlined,
                  label: 'Credencial vinculada',
                ),
              const _InfoChip(
                icon: Icons.sync_alt_rounded,
                label: 'Coexistência Meta',
              ),
            ],
          ),
          const SizedBox(height: 20),
              Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _openWizard(initialStep: 2),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Reconectar / atualizar'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
              if (account.status.toLowerCase() == 'active')
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _confirmDeactivate(account),
                  child: const Text('Desativar conta'),
                )
              else
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _setStatus(account, 'active'),
                  child: const Text('Reativar conta'),
                ),
            ],
          ),
        ],
      ),
    );

    if (!wide) return hero;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: hero),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.xxl,
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pronto para atender',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Com a conta ativa, Conversas e Templates usam este número '
                  'como remetente do tenant.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 14),
                _RequirementRow(
                  icon: Icons.forum_outlined,
                  text: 'Mensagens entram em Conversas',
                ),
                _RequirementRow(
                  icon: Icons.campaign_outlined,
                  text: 'Templates disparam neste número',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeactivate(WhatsAppAccountModel account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Desativar conta?',
          style: TextStyle(color: AppColors.text),
        ),
        content: const Text(
          'A conta fica inativa neste tenant. O envio e a resolução automática '
          'deixam de usar este número até reativar. Nada é apagado na Meta.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _setStatus(account, 'inactive');
    }
  }

  Widget _buildAccountsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contas deste tenant',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ..._accounts.map((account) {
          final color = _statusColor(account.status);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayPhoneNumber.isNotEmpty
                            ? account.displayPhoneNumber
                            : account.displayName,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_statusLabel(account.status)}'
                        '${account.isDefault ? ' · Principal' : ''}',
                        style: TextStyle(color: color, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!account.isDefault &&
                    account.status.toLowerCase() == 'active')
                  TextButton(
                    onPressed: _busy ? null : () => _setDefault(account),
                    child: const Text('Tornar principal'),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primarySoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSoft, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}
