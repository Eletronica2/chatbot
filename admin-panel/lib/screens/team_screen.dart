import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tenant_user.dart';
import '../services/auth_service.dart';
import '../services/tenant_user_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Gestão de equipe do tenant atual (owner/manager) — Fase 10.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

enum _MemberAction { edit, toggleStatus, reset }

class _TeamScreenState extends State<TeamScreen> {
  static const List<String> _roles = <String>['agent', 'manager', 'owner'];
  static const List<String> _statuses = <String>[
    'active',
    'inactive',
    'invited',
  ];

  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _inviting = false;
  String? _error;
  String? _busyUserId;
  String? _statusFilter;
  List<TenantUserModel> _users = <TenantUserModel>[];

  String get _tenantId => authService.tenantId ?? '';

  String get _companyName {
    final friendly = authService.activeTenantDisplayName?.trim() ?? '';
    if (friendly.isNotEmpty) return friendly;
    final id = authService.tenantId?.trim() ?? '';
    if (id.isEmpty) return 'sua empresa';
    return id;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_tenantId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Tenant não identificado. Faça login novamente.';
        _users = <TenantUserModel>[];
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

  bool _isSelf(TenantUserModel user) {
    final current = authService.currentUser;
    if (current == null) return false;
    if (current.userId.isNotEmpty && current.userId == user.userId) {
      return true;
    }
    final email = current.email.trim().toLowerCase();
    return email.isNotEmpty && email == user.email.trim().toLowerCase();
  }

  List<TenantUserModel> get _filteredUsers {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _users.where((user) {
      if (_statusFilter != null &&
          user.status.toLowerCase() != _statusFilter!.toLowerCase()) {
        return false;
      }
      if (query.isEmpty) return true;
      final role = user.role;
      final status = user.status;
      return user.displayName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          _roleLabel(role).toLowerCase().contains(query) ||
          role.toLowerCase().contains(query) ||
          _statusLabel(status).toLowerCase().contains(query) ||
          status.toLowerCase().contains(query);
    }).toList();
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
        return role.isEmpty ? 'Usuário' : role;
    }
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
        return 'Ativo';
      case 'inactive':
        return 'Inativo';
      case 'invited':
        return 'Convite pendente';
      default:
        return status.isEmpty ? '—' : status;
    }
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
        return AppColors.success;
      case 'invited':
        return AppColors.warning;
      case 'inactive':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  String _initials(TenantUserModel user) {
    final name = user.displayName.trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
      }
      return name[0].toUpperCase();
    }
    final email = user.email.trim();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }

  String _lastLoginLabel(TenantUserModel user) {
    final at = user.lastLoginAt;
    if (at == null) return 'Sem acesso registrado';
    final local = at.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Último acesso agora';
    if (diff.inMinutes < 60) {
      return 'Último acesso há ${diff.inMinutes} min';
    }
    if (diff.inHours < 24) return 'Último acesso há ${diff.inHours} h';
    if (diff.inDays < 7) return 'Último acesso há ${diff.inDays} d';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Último acesso ${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  EdgeInsets _dialogInsets(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 420 ? 16.0 : 24.0;
    return EdgeInsets.fromLTRB(pad, 24, pad, 24);
  }

  double _dialogWidth(BuildContext context, {double max = 420}) {
    final width = MediaQuery.sizeOf(context).width;
    return width < 520 ? width - 48 : max;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showInviteDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    var role = 'agent';
    String? dialogError;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (nameCtrl.text.trim().isEmpty ||
                  emailCtrl.text.trim().isEmpty) {
                setDialogState(() => dialogError = 'Preencha nome e e-mail.');
                return;
              }
              setDialogState(() {
                dialogError = null;
                submitting = true;
                _inviting = true;
              });
              try {
                final result = await tenantUserService.inviteUser(
                  tenantId: _tenantId,
                  email: emailCtrl.text.trim(),
                  displayName: nameCtrl.text.trim(),
                  role: role,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                await _load();
                if (!mounted) return;
                await _showTokenDialog(
                  title: 'Convite gerado',
                  description:
                      'Envie o link abaixo para a pessoa concluir o acesso. '
                      'O aceite público usa o mesmo contrato da tela de convite.',
                  token: result,
                );
              } catch (err) {
                setDialogState(() {
                  dialogError = '$err';
                  submitting = false;
                });
              } finally {
                if (mounted) setState(() => _inviting = false);
              }
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              insetPadding: _dialogInsets(context),
              title: const Text(
                'Convidar para a equipe',
                style: TextStyle(color: AppColors.text),
              ),
              content: SizedBox(
                width: _dialogWidth(context),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Gera um convite com link/token. A pessoa define a senha ao aceitar.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: AppColors.text),
                        decoration: const InputDecoration(labelText: 'Nome'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: AppColors.text),
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: role,
                        dropdownColor: AppColors.surface,
                        decoration: const InputDecoration(labelText: 'Perfil'),
                        items: [
                          for (final r in _roles)
                            DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => role = value);
                                }
                              },
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogError!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? 'Gerando...' : 'Gerar convite'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
  }

  Future<void> _showEditDialog(TenantUserModel user) async {
    final nameCtrl = TextEditingController(text: user.displayName);
    var role = _roles.contains(user.role.toLowerCase())
        ? user.role.toLowerCase()
        : user.role;
    var status = _statuses.contains(user.status.toLowerCase())
        ? user.status.toLowerCase()
        : user.status;
    String? dialogError;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (nameCtrl.text.trim().isEmpty) {
                setDialogState(() => dialogError = 'Informe o nome.');
                return;
              }
              setDialogState(() {
                dialogError = null;
                submitting = true;
              });
              try {
                await tenantUserService.updateUser(
                  tenantId: _tenantId,
                  userId: user.userId,
                  displayName: nameCtrl.text.trim(),
                  role: role,
                  status: status,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                await _load();
                if (!mounted) return;
                _snack('Membro atualizado.');
              } catch (err) {
                setDialogState(() {
                  dialogError = '$err';
                  submitting = false;
                });
              }
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              insetPadding: _dialogInsets(context),
              title: const Text(
                'Editar membro',
                style: TextStyle(color: AppColors.text),
              ),
              content: SizedBox(
                width: _dialogWidth(context),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: AppColors.text),
                        decoration: const InputDecoration(labelText: 'Nome'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: TextEditingController(text: user.email),
                        enabled: false,
                        style: const TextStyle(color: AppColors.textMuted),
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: role,
                        dropdownColor: AppColors.surface,
                        decoration: const InputDecoration(labelText: 'Perfil'),
                        items: [
                          for (final r in _roles)
                            DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => role = value);
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: status,
                        dropdownColor: AppColors.surface,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final s in _statuses)
                            DropdownMenuItem(
                              value: s,
                              child: Text(_statusLabel(s)),
                            ),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => status = value);
                                }
                              },
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          dialogError!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(submitting ? 'Salvando...' : 'Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
  }

  Future<void> _confirmToggleStatus(TenantUserModel user) async {
    final isActive = user.status.toLowerCase() == 'active';
    final next = isActive ? 'inactive' : 'active';
    final self = _isSelf(user);
    final label = user.displayName.trim().isEmpty
        ? user.email
        : user.displayName.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: _dialogInsets(dialogContext),
          title: Text(
            isActive ? 'Desativar acesso?' : 'Reativar acesso?',
            style: const TextStyle(color: AppColors.text),
          ),
          content: SizedBox(
            width: _dialogWidth(dialogContext, max: 400),
            child: Text(
              self
                  ? 'Você está alterando o status da própria conta. '
                      'Confirme apenas se tiver certeza.'
                  : isActive
                      ? '$label ficará com status Inativo e poderá perder o '
                          'acesso ao painel.'
                      : '$label voltará com status Ativo.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: isActive
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isActive ? 'Desativar' : 'Reativar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busyUserId = user.userId);
    try {
      await tenantUserService.updateUser(
        tenantId: _tenantId,
        userId: user.userId,
        status: next,
      );
      await _load();
      if (!mounted) return;
      _snack(next == 'active' ? 'Acesso reativado.' : 'Acesso desativado.');
    } catch (err) {
      if (!mounted) return;
      _snack('Não foi possível atualizar: $err');
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _confirmPasswordReset(TenantUserModel user) async {
    final label = user.displayName.trim().isEmpty
        ? user.email
        : user.displayName.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: _dialogInsets(dialogContext),
          title: const Text(
            'Gerar redefinição de senha?',
            style: TextStyle(color: AppColors.text),
          ),
          content: SizedBox(
            width: _dialogWidth(dialogContext, max: 400),
            child: Text(
              'Será gerado um link/token para $label. Isso não altera a senha '
              'imediatamente — a pessoa redefine ao abrir o link.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Gerar link'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busyUserId = user.userId);
    try {
      final result = await tenantUserService.createPasswordReset(
        tenantId: _tenantId,
        userId: user.userId,
      );
      if (!mounted) return;
      await _showTokenDialog(
        title: 'Redefinição gerada',
        description:
            'Compartilhe o link ou token abaixo. A tela pública de reset '
            'permanece a da Fase 3.',
        token: result,
      );
    } catch (err) {
      if (!mounted) return;
      _snack('Não foi possível gerar o reset: $err');
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _showTokenDialog({
    required String title,
    required String description,
    required TenantUserActionTokenModel token,
  }) async {
    final link = token.actionUrl.isNotEmpty ? token.actionUrl : token.token;
    final emailStatus = token.emailStatus?.trim();
    final emailDelivered = emailStatus == 'sent';
    final String emailLine;
    if (emailStatus == null || emailStatus.isEmpty) {
      emailLine = 'E-mail: não enviado automaticamente';
    } else if (emailDelivered) {
      emailLine = 'E-mail: enviado';
    } else {
      final err = token.emailError?.trim();
      final suffix =
          err != null && err.isNotEmpty ? ' ($err)' : '';
      emailLine = 'E-mail: $emailStatus$suffix';
    }

    String? expiresLine;
    if (token.expiresAt != null) {
      final e = token.expiresAt!.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      expiresLine =
          'Expira em ${two(e.day)}/${two(e.month)}/${e.year} '
          '${two(e.hour)}:${two(e.minute)}';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          insetPadding: _dialogInsets(dialogContext),
          title: Text(title, style: const TextStyle(color: AppColors.text)),
          content: SizedBox(
            width: _dialogWidth(dialogContext, max: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    label: 'email_status $emailStatus',
                    child: Text(
                      emailLine,
                      style: TextStyle(
                        color: emailDelivered
                            ? AppColors.success
                            : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (expiresLine != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      expiresLine,
                      style: const TextStyle(
                        color: AppColors.textSoft,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SelectableText(
                    link,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (!mounted) return;
                _snack('Copiado para a área de transferência.');
              },
              child: const Text('Copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 800;
    final filtered = _filteredUsers;

    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: Padding(
        padding: AppPageInsets.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TeamHeader(
              companyName: _companyName,
              memberCount: _users.length,
              loading: _loading,
              compact: compact,
              onInvite: _loading || _inviting ? null : _showInviteDialog,
              onRefresh: _loading ? null : _load,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.92),
                  borderRadius: AppRadius.xl,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(color: AppColors.text),
                            decoration: InputDecoration(
                              hintText: 'Buscar por nome, e-mail, perfil…',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                              ),
                              suffixIcon: _searchCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar',
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatusFilterChip(
                                label: 'Todos',
                                selected: _statusFilter == null,
                                onTap: () =>
                                    setState(() => _statusFilter = null),
                              ),
                              for (final status in _statuses)
                                _StatusFilterChip(
                                  label: _statusLabel(status),
                                  selected: _statusFilter == status,
                                  onTap: () => setState(
                                    () => _statusFilter = status,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    Expanded(child: _buildBody(filtered, compact)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<TenantUserModel> filtered, bool compact) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PremiumEmptyPanel(
                icon: Icons.group_outlined,
                title: 'Nenhum membro listado',
                description:
                    'Convide a primeira pessoa para acessar o atendimento de '
                    '$_companyName.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _inviting ? null : _showInviteDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Convidar'),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: PremiumEmptyPanel(
            icon: Icons.search_off_rounded,
            title: 'Nenhum resultado',
            description: 'Ajuste a busca ou o filtro de status.',
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = filtered[index];
        return _MemberTile(
          user: user,
          compact: compact,
          isSelf: _isSelf(user),
          busy: _busyUserId == user.userId,
          initials: _initials(user),
          roleLabel: _roleLabel(user.role),
          statusLabel: _statusLabel(user.status),
          statusColor: _statusColor(user.status),
          lastLoginLabel: _lastLoginLabel(user),
          onEdit: () => _showEditDialog(user),
          onToggleStatus: () => _confirmToggleStatus(user),
          onReset: () => _confirmPasswordReset(user),
        );
      },
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({
    required this.companyName,
    required this.memberCount,
    required this.loading,
    required this.compact,
    required this.onInvite,
    required this.onRefresh,
  });

  final String companyName;
  final int memberCount;
  final bool loading;
  final bool compact;
  final VoidCallback? onInvite;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final countLabel = loading
        ? 'Carregando membros…'
        : memberCount == 1
            ? '1 membro'
            : '$memberCount membros';

    final invite = FilledButton.icon(
      onPressed: onInvite,
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: const Text('Convidar'),
    );
    final refresh = IconButton(
      tooltip: 'Atualizar',
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh_rounded),
    );

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Equipe',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Quem tem acesso ao atendimento de $companyName?',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          countLabel,
          style: const TextStyle(
            color: AppColors.textSoft,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.border),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: intro),
                    refresh,
                  ],
                ),
                const SizedBox(height: 12),
                invite,
              ],
            )
          : Row(
              children: [
                Expanded(child: intro),
                refresh,
                const SizedBox(width: 8),
                invite,
              ],
            ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : AppMotion.hoverOf(context),
          curve: AppMotion.hoverCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.16)
                : AppColors.surfaceSoft,
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primarySoft : AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatefulWidget {
  const _MemberTile({
    required this.user,
    required this.compact,
    required this.isSelf,
    required this.busy,
    required this.initials,
    required this.roleLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.lastLoginLabel,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onReset,
  });

  final TenantUserModel user;
  final bool compact;
  final bool isSelf;
  final bool busy;
  final String initials;
  final String roleLabel;
  final String statusLabel;
  final Color statusColor;
  final String lastLoginLabel;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onReset;

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = user.displayName.trim().isEmpty
        ? (user.email.trim().isEmpty ? 'Sem nome' : user.email)
        : user.displayName.trim();
    final isActive = user.status.toLowerCase() == 'active';

    final menu = Semantics(
      label: 'Opções do membro',
      button: true,
      child: PopupMenuButton<_MemberAction>(
        tooltip: 'Opções do membro',
        enabled: !widget.busy,
        onSelected: (action) {
          switch (action) {
            case _MemberAction.edit:
              widget.onEdit();
            case _MemberAction.toggleStatus:
              widget.onToggleStatus();
            case _MemberAction.reset:
              widget.onReset();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: _MemberAction.edit,
            child: Text('Editar'),
          ),
          PopupMenuItem(
            value: _MemberAction.toggleStatus,
            child: Text(isActive ? 'Desativar acesso' : 'Reativar acesso'),
          ),
          const PopupMenuItem(
            value: _MemberAction.reset,
            child: Text('Gerar redefinição de senha'),
          ),
        ],
        icon: widget.busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_vert_rounded),
      ),
    );

    final badges = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (widget.isSelf)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: AppRadius.pill,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Você',
              style: TextStyle(
                color: AppColors.primarySoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.statusColor.withValues(alpha: 0.14),
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            widget.statusLabel,
            style: TextStyle(
              color: widget.statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primary.withValues(alpha: 0.18),
      child: Text(
        widget.initials,
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.compact) ...[
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            user.email,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ] else ...[
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              badges,
            ],
          ),
          const SizedBox(height: 2),
          Text(
            user.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );

    final meta = Column(
      crossAxisAlignment:
          widget.compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          widget.roleLabel,
          style: const TextStyle(
            color: AppColors.textSoft,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.lastLoginLabel,
          style: const TextStyle(
            color: AppColors.textSoft,
            fontSize: 11,
          ),
        ),
      ],
    );

    final body = widget.compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: identity),
                  menu,
                ],
              ),
              const SizedBox(height: 10),
              badges,
              const SizedBox(height: 8),
              meta,
            ],
          )
        : Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(flex: 3, child: identity),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: meta),
              menu,
            ],
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.hoverOf(context),
        curve: AppMotion.hoverCurve,
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 12 : 14,
          vertical: widget.compact ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.surfaceAlt : AppColors.surfaceSoft,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.border),
        ),
        child: body,
      ),
    );
  }
}
