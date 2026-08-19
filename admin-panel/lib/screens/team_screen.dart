import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tenant_user.dart';
import '../services/auth_service.dart';
import '../services/tenant_user_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Gestão de equipe do tenant atual (owner/manager).
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool _loading = true;
  bool _inviting = false;
  String? _error;
  List<TenantUserModel> _users = <TenantUserModel>[];

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
        _error = 'Tenant não identificado. Faça login novamente.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await tenantUserService.listUsers(_tenantId);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = '$err';
        _loading = false;
      });
    }
  }

  Future<void> _showInviteDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    var role = 'agent';
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty) {
                setDialogState(() => dialogError = 'Preencha nome e e-mail.');
                return;
              }
              setDialogState(() {
                dialogError = null;
                _inviting = true;
              });
              try {
                final result = await tenantUserService.inviteUser(
                  tenantId: _tenantId,
                  email: emailCtrl.text.trim(),
                  displayName: nameCtrl.text.trim(),
                  role: role,
                );
                Navigator.of(dialogContext).pop();
                await _load();
                if (!mounted) return;
                await _showTokenDialog(result);
              } catch (err) {
                setDialogState(() => dialogError = '$err');
              } finally {
                if (mounted) setState(() => _inviting = false);
              }
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              title: const Text('Convidar usuário', style: TextStyle(color: AppColors.text)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: const InputDecoration(labelText: 'E-mail'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: role,
                      dropdownColor: AppColors.surface,
                      decoration: const InputDecoration(labelText: 'Papel'),
                      items: const [
                        DropdownMenuItem(value: 'agent', child: Text('Atendente')),
                        DropdownMenuItem(value: 'manager', child: Text('Gerente')),
                        DropdownMenuItem(value: 'owner', child: Text('Admin da empresa')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => role = value);
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(dialogError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _inviting ? null : submit,
                  child: Text(_inviting ? 'Enviando...' : 'Gerar convite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTokenDialog(TenantUserActionTokenModel token) async {
    final link = token.actionUrl.isNotEmpty ? token.actionUrl : token.token;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Convite gerado', style: TextStyle(color: AppColors.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Envie o link ou token abaixo para a pessoa concluir o acesso.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(link, style: const TextStyle(color: AppColors.text, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copiado para a área de transferência.')),
              );
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Admin da empresa';
      case 'manager':
        return 'Gerente';
      case 'agent':
        return 'Atendente';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: Padding(
        padding: AppPageInsets.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PremiumGlassCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 640;
                  final invite = FilledButton.icon(
                    onPressed: _loading ? null : _showInviteDialog,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Convidar'),
                  );
                  final intro = const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Equipe',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Convide atendentes e gerentes para operar o WhatsApp da sua empresa.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                      ),
                    ],
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [intro, const SizedBox(height: 14), invite],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: intro),
                      invite,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: PremiumGlassCard(
                padding: EdgeInsets.zero,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                                  const SizedBox(height: 12),
                                  FilledButton(onPressed: _load, child: const Text('Tentar novamente')),
                                ],
                              ),
                            ),
                          )
                        : _users.isEmpty
                            ? const PremiumEmptyPanel(
                                icon: Icons.group_outlined,
                                title: 'Nenhum usuário listado',
                                description: 'Convide a primeira pessoa da equipe para atender pelo painel.',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _users.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final user = _users[index];
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSoft,
                                      borderRadius: AppRadius.md,
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                          child: Text(
                                            user.displayName.isNotEmpty
                                                ? user.displayName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(color: AppColors.primarySoft),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user.displayName,
                                                style: const TextStyle(
                                                  color: AppColors.text,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                user.email,
                                                style: const TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _roleLabel(user.role),
                                          style: const TextStyle(
                                            color: AppColors.textSoft,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: user.status.toLowerCase() == 'active'
                                                ? AppColors.success.withValues(alpha: 0.15)
                                                : AppColors.warning.withValues(alpha: 0.15),
                                            borderRadius: AppRadius.pill,
                                          ),
                                          child: Text(
                                            user.status.toLowerCase() == 'active'
                                                ? 'Ativo'
                                                : user.status,
                                            style: TextStyle(
                                              color: user.status.toLowerCase() == 'active'
                                                  ? AppColors.success
                                                  : AppColors.warning,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
