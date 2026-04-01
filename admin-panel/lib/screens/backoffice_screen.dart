import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_audit_entry.dart';
import '../models/subscription_info.dart';
import '../models/tenant_admin.dart';
import '../models/tenant_user.dart';
import '../models/whatsapp_account.dart';
import '../services/admin_audit_service.dart';
import '../services/admin_tenant_service.dart';
import '../services/auth_service.dart';
import '../services/flow_admin_service.dart';
import '../services/subscription_service.dart';
import '../services/tenant_user_service.dart';
import '../services/whatsapp_account_service.dart';
import '../widgets/app_sidebar.dart';
import 'settings_screen.dart';

const _kBg = Color(0xFF0B1120);
const _kSurface = Color(0xFF111827);
const _kCard = Color(0xFF1F2937);
const _kInput = Color(0xFF0F172A);
const _kBorder = Color(0xFF374151);
const _kText = Color(0xFFE2E8F0);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kAccent = Color(0xFF7C8CFF);
const _kAccentSoft = Color(0xFF818CF8);
const _kSuccess = Color(0xFF10B981);
const _kDanger = Color(0xFFEF4444);

String _planLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'starter':
      return 'Inicial';
    case 'growth':
      return 'Crescimento';
    case 'pro':
      return 'Profissional';
    case 'enterprise':
      return 'Empresarial';
    default:
      return value.isEmpty ? 'Plano' : value;
  }
}

String _statusLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'active':
      return 'Ativo';
    case 'trialing':
      return 'Em teste';
    case 'inactive':
      return 'Inativo';
    case 'invited':
      return 'Convidado';
    case 'past_due':
      return 'Pagamento pendente';
    case 'canceled':
      return 'Cancelado';
    default:
      return value.isEmpty ? 'Sem status' : value;
  }
}

String _roleLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'owner':
      return 'Proprietário';
    case 'manager':
      return 'Gerente';
    case 'agent':
      return 'Atendente';
    case 'system_admin':
    case 'system-admin':
      return 'Administrador do sistema';
    case 'superadmin':
    case 'super_admin':
      return 'Superadministrador';
    default:
      return value.isEmpty ? 'Usuário' : value;
  }
}

class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({
    super.key,
    required this.onLogout,
    this.embedded = false,
    this.onOpenTenantFlows,
  });

  final VoidCallback onLogout;
  final bool embedded;
  final VoidCallback? onOpenTenantFlows;

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen> {
  static const List<String> _planOptions = <String>[
    'starter',
    'growth',
    'pro',
    'enterprise',
  ];

  static const List<String> _statusOptions = <String>[
    'active',
    'trialing',
    'inactive',
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _limitCtrl = TextEditingController();

  bool _loadingTenants = true;
  bool _loadingDetails = false;
  bool _savingPlan = false;
  bool _savingAccount = false;
  bool _savingUser = false;
  String? _settingDefaultAccountKey;
  String? _resettingUserId;

  List<TenantAdminSummary> _tenants = <TenantAdminSummary>[];
  List<TenantAdminSummary> _filteredTenants = <TenantAdminSummary>[];
  TenantAdminSummary? _selectedTenant;
  SubscriptionInfo? _subscription;
  List<WhatsAppAccountModel> _accounts = <WhatsAppAccountModel>[];
  List<TenantUserModel> _users = <TenantUserModel>[];
  List<FlowSummaryModel> _flows = <FlowSummaryModel>[];
  List<AdminAuditEntryModel> _auditEntries = <AdminAuditEntryModel>[];

  String _planValue = _planOptions.first;
  String _statusValue = _statusOptions.first;

  bool get _isSystemTenantContext {
    final tenant = _selectedTenant;
    final homeTenantId = authService.homeTenantId;
    return authService.isSuperadmin &&
        tenant != null &&
        homeTenantId != null &&
        tenant.tenantId == homeTenantId;
  }

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTenants() async {
    setState(() => _loadingTenants = true);
    try {
      final tenants = await adminTenantService.listTenants();
      if (!mounted) return;

      final activeTenantId = authService.tenantId;
      final homeTenantId = authService.homeTenantId;
      TenantAdminSummary? selected;

      if (activeTenantId != null && activeTenantId.isNotEmpty) {
        for (final item in tenants) {
          if (item.tenantId == activeTenantId) {
            selected = item;
            break;
          }
        }
      }

      if (selected == null &&
          authService.isSuperadmin &&
          homeTenantId != null &&
          homeTenantId.isNotEmpty) {
        for (final item in tenants) {
          if (item.tenantId != homeTenantId) {
            selected = item;
            break;
          }
        }
      }

      selected ??= tenants.isNotEmpty ? tenants.first : null;

      setState(() {
        _tenants = tenants;
        _filteredTenants = _filterTenants(_searchCtrl.text, tenants);
        _selectedTenant = selected;
        _loadingTenants = false;
      });

      if (selected != null) {
        await _selectTenant(selected);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _loadingTenants = false);
      _showError('Não foi possível carregar os clientes: $err');
    }
  }

  List<TenantAdminSummary> _filterTenants(
    String query,
    List<TenantAdminSummary> source,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return List<TenantAdminSummary>.from(source);
    }
    return source.where((tenant) {
      return tenant.name.toLowerCase().contains(normalized) ||
          tenant.tenantId.toLowerCase().contains(normalized) ||
          tenant.email.toLowerCase().contains(normalized) ||
          (tenant.ownerEmail ?? '').toLowerCase().contains(normalized);
    }).toList();
  }

  void _onSearchChanged(String value) {
    setState(() => _filteredTenants = _filterTenants(value, _tenants));
  }

  Future<void> _selectTenant(TenantAdminSummary tenant) async {
    setState(() {
      _selectedTenant = tenant;
      _loadingDetails = true;
    });

    await authService.setActiveTenantId(tenant.tenantId);

    if (_isSystemTenantContext) {
      if (!mounted) return;
      setState(() {
        _subscription = null;
        _accounts = <WhatsAppAccountModel>[];
        _users = <TenantUserModel>[];
        _flows = <FlowSummaryModel>[];
        _auditEntries = <AdminAuditEntryModel>[];
        _planValue = _planOptions.first;
        _statusValue = _statusOptions.first;
        _limitCtrl.clear();
        _loadingDetails = false;
      });
      return;
    }

    try {
      final subscription = await subscriptionService.fetchSubscription(
        tenant.tenantId,
      );
      final accounts = await whatsAppAccountService.listAccounts(tenant.tenantId);
      final users = await tenantUserService.listUsers(tenant.tenantId);
      final flows = await flowAdminService.listFlows();
      final auditEntries = await adminAuditService.listAuditLogs();
      if (!mounted) return;
      setState(() {
        _subscription = subscription;
        _accounts = accounts;
        _users = users;
        _flows = flows;
        _auditEntries = auditEntries;
        _planValue = subscription.plan;
        _statusValue = subscription.status;
        _limitCtrl.text = subscription.monthlyMessageLimit.toString();
        _loadingDetails = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _loadingDetails = false);
      _showError('Não foi possível carregar os detalhes do cliente: $err');
    }
  }

  void _stepPlan(int delta) {
    final currentIndex = _planOptions.indexOf(_planValue);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (safeIndex + delta).clamp(0, _planOptions.length - 1);
    setState(() => _planValue = _planOptions[nextIndex]);
  }

  Future<void> _savePlan() async {
    final tenant = _selectedTenant;
    if (tenant == null || _isSystemTenantContext) return;

    final limit = int.tryParse(_limitCtrl.text.trim());
    setState(() => _savingPlan = true);
    try {
      final updated = await subscriptionService.updateSubscription(
        tenantId: tenant.tenantId,
        plan: _planValue,
        status: _statusValue,
        monthlyMessageLimit: limit,
      );
      if (!mounted) return;
      setState(() => _subscription = updated);
      _showOk('Plano atualizado com sucesso.');
      await _loadTenants();
    } catch (err) {
      if (!mounted) return;
      _showError('Não foi possível salvar o plano: $err');
    } finally {
      if (mounted) {
        setState(() => _savingPlan = false);
      }
    }
  }

  Future<void> _setDefaultAccount(WhatsAppAccountModel account) async {
    final tenant = _selectedTenant;
    if (tenant == null || _settingDefaultAccountKey == account.accountKey) {
      return;
    }

    setState(() => _settingDefaultAccountKey = account.accountKey);
    try {
      await whatsAppAccountService.updateAccount(
        tenantId: tenant.tenantId,
        accountKey: account.accountKey,
        isDefault: true,
      );
      await _selectTenant(tenant);
      if (!mounted) return;
      _showOk('Conta principal atualizada com sucesso.');
    } catch (err) {
      if (!mounted) return;
      _showError('Não foi possível alterar a conta principal: $err');
    } finally {
      if (mounted) {
        setState(() => _settingDefaultAccountKey = null);
      }
    }
  }

  Future<void> _showCreateTenantDialog() async {
    final tenantIdCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ownerNameCtrl = TextEditingController();
    final ownerEmailCtrl = TextEditingController();
    final ownerPasswordCtrl = TextEditingController(text: 'senha123');
    final limitCtrl = TextEditingController(text: '1000');

    String plan = _planOptions.first;
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (tenantIdCtrl.text.trim().isEmpty ||
                  nameCtrl.text.trim().isEmpty ||
                  emailCtrl.text.trim().isEmpty ||
                  ownerNameCtrl.text.trim().isEmpty ||
                  ownerEmailCtrl.text.trim().isEmpty ||
                  ownerPasswordCtrl.text.trim().isEmpty) {
                setDialogState(() {
                  error = 'Preencha todos os campos obrigatórios.';
                });
                return;
              }

              setDialogState(() {
                saving = true;
                error = null;
              });

              try {
                final created = await adminTenantService.createTenant(
                  tenantId: tenantIdCtrl.text.trim(),
                  name: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  ownerName: ownerNameCtrl.text.trim(),
                  ownerEmail: ownerEmailCtrl.text.trim(),
                  ownerPassword: ownerPasswordCtrl.text.trim(),
                  plan: plan,
                  monthlyMessageLimit: int.tryParse(limitCtrl.text.trim()),
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _loadTenants();
                await _selectTenant(created);
                _showOk('Cliente criado com sucesso.');
              } catch (err) {
                setDialogState(() {
                  error = '$err';
                  saving = false;
                });
              }
            }

            return AlertDialog(
              backgroundColor: _kCard,
              title: const Text(
                'Novo cliente',
                style: TextStyle(color: _kText),
              ),
              content: SizedBox(
                width: 470,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DialogField(
                        controller: tenantIdCtrl,
                        label: 'Identificador do cliente',
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: nameCtrl,
                        label: 'Nome da empresa',
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: emailCtrl,
                        label: 'Email da empresa',
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: ownerNameCtrl,
                        label: 'Nome do responsável',
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: ownerEmailCtrl,
                        label: 'Email do responsável',
                      ),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: ownerPasswordCtrl,
                        label: 'Senha inicial',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogSelect(
                              label: 'Plano inicial',
                              value: plan,
                              items: _planOptions,
                              labelBuilder: _planLabel,
                              onChanged: (value) {
                                setDialogState(() => plan = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DialogField(
                              controller: limitCtrl,
                              label: 'Limite mensal',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: _kDanger,
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
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving ? null : submit,
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  child: Text(saving ? 'Criando...' : 'Criar cliente'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAccountDialog({WhatsAppAccountModel? account}) async {
    final tenant = _selectedTenant;
    if (tenant == null || _isSystemTenantContext) return;

    final bool isEditing = account != null;
    final accountKeyCtrl = TextEditingController(text: account?.accountKey ?? '');
    final displayNameCtrl = TextEditingController(text: account?.displayName ?? '');
    final phoneNumberIdCtrl = TextEditingController(text: account?.phoneNumberId ?? '');
    final displayPhoneCtrl = TextEditingController(text: account?.displayPhoneNumber ?? '');
    final verifyTokenCtrl = TextEditingController(text: account?.verifyToken ?? '');
    final accessTokenCtrl = TextEditingController();

    String status = account?.status ?? 'active';
    bool isDefault = account?.isDefault ?? _accounts.isEmpty;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (accountKeyCtrl.text.trim().isEmpty ||
                  displayNameCtrl.text.trim().isEmpty ||
                  phoneNumberIdCtrl.text.trim().isEmpty ||
                  displayPhoneCtrl.text.trim().isEmpty) {
                setDialogState(() {
                  error = 'Preencha os campos obrigatórios da conta.';
                });
                return;
              }

              setState(() => _savingAccount = true);
              setDialogState(() => error = null);

              try {
                if (isEditing) {
                  await whatsAppAccountService.updateAccount(
                    tenantId: tenant.tenantId,
                    accountKey: account.accountKey,
                    displayName: displayNameCtrl.text.trim(),
                    phoneNumberId: phoneNumberIdCtrl.text.trim(),
                    displayPhoneNumber: displayPhoneCtrl.text.trim(),
                    accessToken: accessTokenCtrl.text.trim().isEmpty
                        ? null
                        : accessTokenCtrl.text.trim(),
                    verifyToken: verifyTokenCtrl.text.trim(),
                    status: status,
                    isDefault: isDefault,
                  );
                } else {
                  await whatsAppAccountService.createAccount(
                    tenantId: tenant.tenantId,
                    accountKey: accountKeyCtrl.text.trim(),
                    displayName: displayNameCtrl.text.trim(),
                    phoneNumberId: phoneNumberIdCtrl.text.trim(),
                    displayPhoneNumber: displayPhoneCtrl.text.trim(),
                    accessToken: accessTokenCtrl.text.trim(),
                    verifyToken: verifyTokenCtrl.text.trim(),
                    status: status,
                    isDefault: isDefault,
                  );
                }

                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _selectTenant(tenant);
                _showOk(isEditing ? 'Conta atualizada com sucesso.' : 'Conta criada com sucesso.');
              } catch (err) {
                setDialogState(() => error = '$err');
              } finally {
                if (mounted) {
                  setState(() => _savingAccount = false);
                }
              }
            }

            return AlertDialog(
              backgroundColor: _kCard,
              title: Text(
                isEditing ? 'Editar conta WhatsApp' : 'Nova conta WhatsApp',
                style: const TextStyle(color: _kText),
              ),
              content: SizedBox(
                width: 470,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DialogField(controller: accountKeyCtrl, label: 'Identificador da conta', enabled: !isEditing),
                      const SizedBox(height: 10),
                      _DialogField(controller: displayNameCtrl, label: 'Nome amigável'),
                      const SizedBox(height: 10),
                      _DialogField(controller: phoneNumberIdCtrl, label: 'ID do número no WhatsApp'),
                      const SizedBox(height: 10),
                      _DialogField(controller: displayPhoneCtrl, label: 'Número exibido'),
                      const SizedBox(height: 10),
                      _DialogField(controller: verifyTokenCtrl, label: 'Token de verificação'),
                      const SizedBox(height: 10),
                      _DialogField(
                        controller: accessTokenCtrl,
                        label: isEditing ? 'Novo token de acesso (opcional)' : 'Token de acesso',
                        maxLines: 3,
                      ),
                      if (isEditing && account.maskedAccessToken != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Token salvo: ${account.maskedAccessToken}',
                            style: const TextStyle(color: _kSubtle, fontSize: 11),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                        _DialogSelect(
                          label: 'Status',
                          value: status,
                          items: const <String>['active', 'inactive'],
                          labelBuilder: _statusLabel,
                          onChanged: (value) => setDialogState(() => status = value),
                        ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: isDefault,
                        activeTrackColor: _kAccent,
                        onChanged: (value) => setDialogState(() => isDefault = value),
                        title: const Text(
                          'Usar como conta principal',
                          style: TextStyle(color: _kText, fontSize: 13),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!, style: const TextStyle(color: _kDanger, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _savingAccount ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _savingAccount ? null : submit,
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  child: Text(_savingAccount ? 'Salvando...' : 'Salvar conta'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showInviteUserDialog() async {
    final tenant = _selectedTenant;
    if (tenant == null || _isSystemTenantContext) return;

    final displayNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String role = 'manager';
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (displayNameCtrl.text.trim().isEmpty ||
                  emailCtrl.text.trim().isEmpty) {
                setDialogState(() {
                  error = 'Preencha nome e email do usuário.';
                });
                return;
              }
              setState(() => _savingUser = true);
              setDialogState(() => error = null);
              try {
                final result = await tenantUserService.inviteUser(
                  tenantId: tenant.tenantId,
                  email: emailCtrl.text.trim(),
                  displayName: displayNameCtrl.text.trim(),
                  role: role,
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _selectTenant(tenant);
                await _showActionTokenDialog(
                  title: 'Convite gerado',
                  description:
                      'Envie o link ou o token abaixo para o novo usuário concluir o acesso.',
                  token: result,
                );
              } catch (err) {
                setDialogState(() => error = '$err');
              } finally {
                if (mounted) {
                  setState(() => _savingUser = false);
                }
              }
            }

            return AlertDialog(
              backgroundColor: _kCard,
              title: const Text(
                'Convidar usuário',
                style: TextStyle(color: _kText),
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogField(
                      controller: displayNameCtrl,
                      label: 'Nome do usuário',
                    ),
                    const SizedBox(height: 10),
                    _DialogField(
                      controller: emailCtrl,
                      label: 'Email do usuário',
                    ),
                    const SizedBox(height: 10),
                    _DialogSelect(
                      label: 'Perfil',
                      value: role,
                      items: const <String>['owner', 'manager', 'agent'],
                      labelBuilder: _roleLabel,
                      onChanged: (value) => setDialogState(() => role = value),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: _kDanger, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _savingUser
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _savingUser ? null : submit,
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  child: Text(_savingUser ? 'Gerando...' : 'Gerar convite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditUserDialog(TenantUserModel user) async {
    final tenant = _selectedTenant;
    if (tenant == null || _isSystemTenantContext) return;

    final displayNameCtrl = TextEditingController(text: user.displayName);
    String role = user.role;
    String status = user.status;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (displayNameCtrl.text.trim().isEmpty) {
                setDialogState(() => error = 'Informe o nome do usuário.');
                return;
              }
              setState(() => _savingUser = true);
              setDialogState(() => error = null);
              try {
                await tenantUserService.updateUser(
                  tenantId: tenant.tenantId,
                  userId: user.userId,
                  displayName: displayNameCtrl.text.trim(),
                  role: role,
                  status: status,
                );
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                await _selectTenant(tenant);
                _showOk('Usuário atualizado com sucesso.');
              } catch (err) {
                setDialogState(() => error = '$err');
              } finally {
                if (mounted) {
                  setState(() => _savingUser = false);
                }
              }
            }

            return AlertDialog(
              backgroundColor: _kCard,
              title: const Text(
                'Editar usuário',
                style: TextStyle(color: _kText),
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogField(
                      controller: displayNameCtrl,
                      label: 'Nome do usuário',
                    ),
                    const SizedBox(height: 10),
                    _DialogField(
                      controller: TextEditingController(text: user.email),
                      label: 'Email',
                      enabled: false,
                    ),
                    const SizedBox(height: 10),
                    _DialogSelect(
                      label: 'Perfil',
                      value: role,
                      items: const <String>['owner', 'manager', 'agent'],
                      labelBuilder: _roleLabel,
                      onChanged: (value) => setDialogState(() => role = value),
                    ),
                    const SizedBox(height: 10),
                    _DialogSelect(
                      label: 'Status',
                      value: status,
                      items: const <String>['active', 'inactive', 'invited'],
                      labelBuilder: _statusLabel,
                      onChanged: (value) => setDialogState(() => status = value),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: _kDanger, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _savingUser
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _savingUser ? null : submit,
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  child: Text(_savingUser ? 'Salvando...' : 'Salvar usuário'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateResetForUser(TenantUserModel user) async {
    final tenant = _selectedTenant;
    if (tenant == null) return;
    setState(() => _resettingUserId = user.userId);
    try {
      final result = await tenantUserService.createPasswordReset(
        tenantId: tenant.tenantId,
        userId: user.userId,
      );
      if (!mounted) return;
      await _showActionTokenDialog(
        title: 'Redefinição de senha gerada',
        description:
            'Compartilhe o link ou o token abaixo para o usuário redefinir a senha.',
        token: result,
      );
      await _selectTenant(tenant);
    } catch (err) {
      if (!mounted) return;
      _showError('Não foi possível gerar o reset de senha: $err');
    } finally {
      if (mounted) {
        setState(() => _resettingUserId = null);
      }
    }
  }

  Future<void> _showActionTokenDialog({
    required String title,
    required String description,
    required TenantUserActionTokenModel token,
  }) async {
    final emailStatus = token.emailStatus?.trim();
    final emailDelivered = emailStatus == 'sent';
    final emailStatusLabel = emailStatus == null || emailStatus.isEmpty
        ? 'Não enviado'
        : emailDelivered
            ? 'Email enviado'
            : emailStatus;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _kCard,
          title: Text(title, style: const TextStyle(color: _kText)),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(color: _kMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _MetricBox(label: 'Usuário', value: token.user.email),
                const SizedBox(height: 10),
                _MetricBox(label: 'Entrega por email', value: emailStatusLabel),
                if (token.emailError != null && token.emailError!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MetricBox(label: 'Erro do email', value: token.emailError!),
                ],
                const SizedBox(height: 10),
                _MetricBox(label: 'Token', value: token.token),
                const SizedBox(height: 10),
                _MetricBox(label: 'Link', value: token.actionUrl),
                const SizedBox(height: 10),
                _MetricBox(
                  label: 'Expira em',
                  value: token.expiresAt == null
                      ? 'Não informado'
                      : DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(token.expiresAt!.toLocal()),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openTenantFlows() async {
    if (_selectedTenant == null) return;
    if (_isSystemTenantContext) {
      _showError('A conta do sistema não possui fluxos próprios. Selecione um cliente.');
      return;
    }
    if (widget.onOpenTenantFlows != null) {
      widget.onOpenTenantFlows!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    if (_selectedTenant != null) {
      await _selectTenant(_selectedTenant!);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _kDanger),
    );
  }

  void _showOk(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _kSuccess),
    );
  }

  void _onNavTap(String index) {
    if (index == 'overview' || index == 'conversations') {
      Navigator.of(context).pop();
      return;
    }
    if (index == 'flows') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Não informado';
    return DateFormat('dd/MM/yyyy').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final content = Container(
      color: _kSurface,
      child: Row(
        children: [
          SizedBox(width: 350, child: _buildTenantsPanel()),
          Container(width: 1, color: _kBorder),
          Expanded(child: _buildDetailsPanel()),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          AppSidebar(
            items: const [
              AppSidebarItem(
                id: 'overview',
                label: 'Visão geral',
                icon: Icons.space_dashboard_rounded,
                section: 'Operação',
                helper: 'Resumo do negócio',
              ),
              AppSidebarItem(
                id: 'conversations',
                label: 'Conversas',
                icon: Icons.chat_bubble_outline_rounded,
                section: 'Operação',
                helper: 'Atendimento e inbox',
              ),
              AppSidebarItem(
                id: 'flows',
                label: 'Fluxos',
                icon: Icons.account_tree_outlined,
                section: 'Operação',
                helper: 'Editor do chatbot',
              ),
              AppSidebarItem(
                id: 'billing',
                label: 'Cobrança',
                icon: Icons.credit_card_rounded,
                section: 'Operação',
                helper: 'Planos e cobrança',
              ),
              AppSidebarItem(
                id: 'backoffice',
                label: 'Administração SaaS',
                icon: Icons.apartment_rounded,
                section: 'Operação SaaS',
                helper: 'Clientes e governança',
              ),
            ],
            selectedId: 'backoffice',
            onNavItemTap: _onNavTap,
            userEmail: user?.email ?? 'admin',
            userRole: user?.role,
            activeTenantLabel: _selectedTenant == null
                ? null
                : '${_selectedTenant!.name} (${_selectedTenant!.tenantId})',
            onLogout: widget.onLogout,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildTenantsOverviewCard() {
    final activeCount = _tenants.where((tenant) => tenant.status == 'active').length;
    final selectedLabel = _selectedTenant?.name ?? 'Nenhum cliente selecionado';

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172033), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: _kAccentSoft,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visão operacional',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Acompanhe rapidamente quantos clientes estão ativos e qual contexto está aberto agora.',
                      style: TextStyle(color: _kMuted, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag(
                label: '${_tenants.length} cliente(s)',
                background: const Color(0xFF1E293B),
                foreground: const Color(0xFFE2E8F0),
              ),
              _Tag(
                label: '$activeCount ativo(s)',
                background: const Color(0xFF064E3B),
                foreground: const Color(0xFF6EE7B7),
              ),
              _Tag(
                label: '${_filteredTenants.length} exibido(s)',
                background: const Color(0xFF312E81),
                foreground: const Color(0xFFC7D2FE),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kInput,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cliente em foco',
                  style: TextStyle(color: _kSubtle, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedLabel,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTenantHeroCard(
    TenantAdminSummary tenant,
    SubscriptionInfo? subscription,
  ) {
    final usagePercent = ((subscription?.usagePercent ?? 0) * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172033), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag(
                label: _planLabel(subscription?.plan ?? tenant.plan),
                background: const Color(0xFF312E81),
                foreground: const Color(0xFFC7D2FE),
              ),
              _Tag(
                label: _statusLabel(subscription?.status ?? tenant.status),
                background: (subscription?.active ?? tenant.status == 'active')
                    ? const Color(0xFF064E3B)
                    : const Color(0xFF7F1D1D),
                foreground: (subscription?.active ?? tenant.status == 'active')
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFFFCA5A5),
              ),
              _Tag(
                label: '$usagePercent% de uso',
                background: const Color(0xFF1E293B),
                foreground: const Color(0xFFE2E8F0),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tenant.name,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tenant.tenantId}  |  ${tenant.email}',
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tenant.ownerEmail?.isNotEmpty == true
                          ? 'Responsável principal: ${tenant.ownerEmail}'
                          : 'Responsável principal não informado',
                      style: const TextStyle(
                        color: _kSubtle,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _openTenantFlows,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('Abrir fluxos'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricBox(label: 'Usuários', value: _users.length.toString()),
              _MetricBox(label: 'Fluxos', value: _flows.length.toString()),
              _MetricBox(label: 'WhatsApp', value: _accounts.length.toString()),
              _MetricBox(
                label: 'Renovação',
                value: _formatDate(subscription?.renewalDate),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTenantsPanel() {
    final homeTenantId = authService.homeTenantId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Administração SaaS',
                          style: TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Liste clientes, crie novas contas e acompanhe planos.',
                          style: TextStyle(color: _kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showCreateTenantDialog,
                    style: FilledButton.styleFrom(backgroundColor: _kAccent),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Novo cliente'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: _kText, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente, empresa ou email',
                  hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, color: _kMuted, size: 18),
                  filled: true,
                  fillColor: _kInput,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kAccent),
                  ),
                ),
              ),
              _buildTenantsOverviewCard(),
            ],
          ),
        ),
        Expanded(
          child: _loadingTenants
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filteredTenants.length,
                  itemBuilder: (_, index) {
                    final tenant = _filteredTenants[index];
                    final selected = tenant.tenantId == _selectedTenant?.tenantId;
                    final isHomeTenant = homeTenantId != null &&
                        homeTenantId.isNotEmpty &&
                        tenant.tenantId == homeTenantId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _selectTenant(tenant),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF182235) : _kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selected ? _kAccentSoft : _kBorder),
                            boxShadow: selected
                                ? const [
                                    BoxShadow(
                                      color: Color(0x24000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: selected ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.storefront_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tenant.name,
                                          style: const TextStyle(
                                            color: _kText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          tenant.tenantId,
                                          style: const TextStyle(
                                            color: _kAccentSoft,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F3A2E),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'Em foco',
                                        style: TextStyle(
                                          color: Color(0xFF86EFAC),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tenant.email,
                                style: const TextStyle(color: _kMuted, fontSize: 12),
                              ),
                              if (tenant.ownerEmail != null && tenant.ownerEmail!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Responsável: ${tenant.ownerEmail}',
                                  style: const TextStyle(color: _kSubtle, fontSize: 11),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (isHomeTenant && authService.isSuperadmin)
                                    const _Tag(
                                      label: 'Sistema',
                                      background: Color(0xFF1E293B),
                                      foreground: Color(0xFFBFDBFE),
                                    ),
                                  _Tag(
                                    label: _planLabel(tenant.plan),
                                    background: const Color(0xFF312E81),
                                    foreground: const Color(0xFFC7D2FE),
                                  ),
                                  _Tag(
                                    label: _statusLabel(tenant.status),
                                    background: tenant.status == 'active'
                                        ? const Color(0xFF064E3B)
                                        : const Color(0xFF7F1D1D),
                                    foreground: tenant.status == 'active'
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Atualizado em ${_formatDate(tenant.updatedAt ?? tenant.createdAt)}',
                                style: const TextStyle(
                                  color: _kSubtle,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailsPanel() {
    final tenant = _selectedTenant;
    if (tenant == null) {
      return const Center(
        child: Text(
          'Selecione um cliente para ver os detalhes.',
          style: TextStyle(color: _kMuted),
        ),
      );
    }

    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isSystemTenantContext) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _DetailCard(
          title: 'Conta interna do sistema',
          subtitle: 'Contexto interno do painel SaaS.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tenant.name,
                style: const TextStyle(color: _kText, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Este cliente interno não consome plano, não usa contas WhatsApp e não possui fluxos próprios. Para visualizar ou editar fluxos, selecione um cliente comercial na coluna da esquerda.',
                style: TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricBox(label: 'Cliente interno', value: tenant.tenantId),
                  _MetricBox(label: 'Criado em', value: _formatDate(tenant.createdAt)),
                  const _MetricBox(label: 'Tipo', value: 'Administrador do sistema'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final subscription = _subscription;
    final usagePercent = subscription?.usagePercent ?? 0;
    final canDowngrade = _planOptions.indexOf(_planValue) > 0;
    final canUpgrade = _planOptions.indexOf(_planValue) >= 0 && _planOptions.indexOf(_planValue) < _planOptions.length - 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTenantHeroCard(tenant, subscription),
          const SizedBox(height: 20),
          _DetailCard(
            title: 'Resumo do cliente',
            subtitle: 'Dados básicos, governança e contexto comercial do cliente selecionado.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricBox(label: 'Responsável', value: tenant.ownerEmail ?? 'Não informado'),
                _MetricBox(label: 'Plano atual', value: _planLabel(subscription?.plan ?? tenant.plan)),
                _MetricBox(label: 'Status', value: _statusLabel(subscription?.status ?? tenant.status)),
                _MetricBox(label: 'Criado em', value: _formatDate(tenant.createdAt)),
                _MetricBox(label: 'Última atualização', value: _formatDate(tenant.updatedAt)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Assinatura e cobrança',
            subtitle: 'Upgrade, downgrade, limite mensal e bloqueio visual.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subscription != null && !subscription.active)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F1D1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF7F1D1D)),
                    ),
                    child: const Text(
                      'Este cliente está bloqueado. O cliente ainda consegue visualizar o painel, mas a edição e o envio ficam limitados até a reativação.',
                      style: TextStyle(color: Color(0xFFFECACA), fontSize: 12),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 920;
                    if (compact) {
                      return Column(
                        children: [
                          _DialogSelect(
                            label: 'Plano',
                            value: _planValue,
                            items: _planOptions,
                            labelBuilder: _planLabel,
                            onChanged: (value) => setState(() => _planValue = value),
                          ),
                          const SizedBox(height: 12),
                          _DialogSelect(
                            label: 'Status',
                            value: _statusValue,
                            items: _statusOptions,
                            labelBuilder: _statusLabel,
                            onChanged: (value) => setState(() => _statusValue = value),
                          ),
                          const SizedBox(height: 12),
                          _DialogField(
                            controller: _limitCtrl,
                            label: 'Limite mensal',
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: _DialogSelect(
                            label: 'Plano',
                            value: _planValue,
                            items: _planOptions,
                            labelBuilder: _planLabel,
                            onChanged: (value) => setState(() => _planValue = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogSelect(
                            label: 'Status',
                            value: _statusValue,
                            items: _statusOptions,
                            labelBuilder: _statusLabel,
                            onChanged: (value) => setState(() => _statusValue = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogField(
                            controller: _limitCtrl,
                            label: 'Limite mensal',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canDowngrade ? () => _stepPlan(-1) : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                      label: const Text('Reduzir plano'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canUpgrade ? () => _stepPlan(1) : null,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Aumentar plano'),
                    ),
                    FilledButton.icon(
                      onPressed: _savingPlan ? null : _savePlan,
                      style: FilledButton.styleFrom(backgroundColor: _kAccent),
                      icon: _savingPlan
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_savingPlan ? 'Salvando...' : 'Salvar plano'),
                    ),
                  ],
                ),
                if (subscription != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${subscription.usedMessages} / ${subscription.monthlyMessageLimit} mensagens usadas',
                    style: const TextStyle(color: _kText, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: usagePercent,
                      backgroundColor: _kInput,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usagePercent >= 0.85 ? _kDanger : _kAccentSoft,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Renovação: ${_formatDate(subscription.renewalDate)}',
                    style: const TextStyle(color: _kMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Contas de WhatsApp',
            subtitle: 'Visualize, crie e edite todas as contas do cliente.',
            action: FilledButton.icon(
              onPressed: () => _showAccountDialog(),
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              icon: const Icon(Icons.add_link_rounded, size: 16),
              label: const Text('Nova conta'),
            ),
            child: _accounts.isEmpty
                ? const _EmptyCardState(
                    icon: Icons.mark_chat_unread_outlined,
                    title: 'Nenhuma conta configurada',
                    message: 'Cadastre uma conta WhatsApp para conectar o número do cliente.',
                  )
                : Column(
                    children: _accounts.map((account) {
                      final isUpdatingDefault = _settingDefaultAccountKey == account.accountKey;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kInput,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        account.displayName,
                                        style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${account.displayPhoneNumber}  |  ${account.phoneNumberId}',
                                        style: const TextStyle(color: _kMuted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _Tag(
                                  label: _statusLabel(account.status),
                                  background: account.status == 'active'
                                      ? const Color(0xFF064E3B)
                                      : const Color(0xFF7F1D1D),
                                  foreground: account.status == 'active'
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFFFCA5A5),
                                ),
                                const SizedBox(width: 8),
                                if (account.isDefault)
                                  const _Tag(
                                    label: 'Principal',
                                    background: Color(0xFF312E81),
                                    foreground: Color(0xFFC7D2FE),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'Identificador: ${account.accountKey}',
                                  style: const TextStyle(color: _kSubtle, fontSize: 11),
                                ),
                                Text(
                                  account.maskedAccessToken == null
                                      ? 'Token salvo: não'
                                      : 'Token salvo: ${account.maskedAccessToken}',
                                  style: const TextStyle(color: _kSubtle, fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showAccountDialog(account: account),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Editar'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: account.isDefault || isUpdatingDefault
                                      ? null
                                      : () => _setDefaultAccount(account),
                                  icon: isUpdatingDefault
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.star_outline_rounded, size: 16),
                                  label: Text(account.isDefault ? 'Conta principal' : 'Definir principal'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Usuários do cliente',
            subtitle: 'Convide usuários, ajuste perfis e gere redefinição de senha.',
            action: FilledButton.icon(
              onPressed: _showInviteUserDialog,
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              icon: const Icon(Icons.person_add_alt_rounded, size: 16),
              label: const Text('Convidar usuário'),
            ),
            child: _users.isEmpty
                ? const _EmptyCardState(
                    icon: Icons.group_outlined,
                    title: 'Nenhum usuário adicional',
                    message:
                        'Convide usuários do time do cliente para acessarem o painel.',
                  )
                : Column(
                    children: _users.map((userItem) {
                      final isResetting = _resettingUserId == userItem.userId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kInput,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userItem.displayName,
                                        style: const TextStyle(
                                          color: _kText,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        userItem.email,
                                        style: const TextStyle(
                                          color: _kMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _Tag(
                                  label: _roleLabel(userItem.role),
                                  background: const Color(0xFF312E81),
                                  foreground: const Color(0xFFC7D2FE),
                                ),
                                const SizedBox(width: 8),
                                _Tag(
                                  label: _statusLabel(userItem.status),
                                  background: userItem.status == 'active'
                                      ? const Color(0xFF064E3B)
                                      : const Color(0xFF7F1D1D),
                                  foreground: userItem.status == 'active'
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFFFCA5A5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'Último acesso: ${_formatDate(userItem.lastLoginAt)}',
                                  style: const TextStyle(
                                    color: _kSubtle,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Criado em: ${_formatDate(userItem.createdAt)}',
                                  style: const TextStyle(
                                    color: _kSubtle,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showEditUserDialog(userItem),
                                  icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                                  label: const Text('Gerenciar'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isResetting
                                      ? null
                                      : () => _generateResetForUser(userItem),
                                  icon: isResetting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.lock_reset_rounded,
                                          size: 16,
                                        ),
                                  label: const Text('Redefinir senha'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Fluxos do cliente',
            subtitle: 'O administrador do sistema pode visualizar os fluxos de qualquer cliente.',
            action: OutlinedButton.icon(
              onPressed: _openTenantFlows,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccentSoft,
                side: const BorderSide(color: _kAccentSoft),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Abrir editor'),
            ),
            child: _flows.isEmpty
                ? const _EmptyCardState(
                    icon: Icons.account_tree_outlined,
                    title: 'Nenhum fluxo salvo',
                    message: 'Crie o primeiro fluxo do cliente para montar o atendimento.',
                  )
                : Column(
                    children: _flows.map((flow) {
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kInput,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_tree_outlined, color: _kAccentSoft, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    flow.name,
                                    style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    flow.description?.trim().isNotEmpty == true
                                        ? flow.description!
                                        : 'Fluxo sem descrição cadastrada.',
                                    style: const TextStyle(color: _kMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              flow.startState?.isNotEmpty == true
                                  ? 'Início: ${flow.startState}'
                                  : 'Início não definido',
                              style: const TextStyle(color: _kSubtle, fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _DetailCard(
            title: 'Auditoria recente',
            subtitle: 'Acompanhe as últimas alterações administrativas deste cliente.',
            child: _auditEntries.isEmpty
                ? const _EmptyCardState(
                    icon: Icons.history_toggle_off_rounded,
                    title: 'Sem eventos recentes',
                    message:
                        'As próximas alterações administrativas aparecerão aqui.',
                  )
                : Column(
                    children: _auditEntries.map((entry) {
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kInput,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.summary,
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${entry.action}  |  ${entry.entityType}  |  ${entry.entityKey}',
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Por: ${entry.actorEmail ?? 'sistema'}  |  ${_formatDate(entry.createdAt)}',
                              style: const TextStyle(
                                color: _kSubtle,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 12),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _kSubtle, fontSize: 11)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyCardState extends StatelessWidget {
  const _EmptyCardState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: _kMuted, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _kMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: _kText, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kMuted),
        filled: true,
        fillColor: _kInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kAccent),
        ),
      ),
    );
  }
}

class _DialogSelect extends StatelessWidget {
  const _DialogSelect({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelBuilder,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _kMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kInput,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              dropdownColor: _kCard,
              style: const TextStyle(color: _kText, fontSize: 13),
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(labelBuilder?.call(item) ?? item),
                    ),
                  )
                  .toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  onChanged(newValue);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
