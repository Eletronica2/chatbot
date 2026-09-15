import 'package:flutter/material.dart';

import '../models/conversation_group.dart';
import '../models/tenant_user.dart';
import '../services/auth_service.dart';
import '../services/conversation_group_service.dart';
import '../services/tenant_user_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Grupos de atendimento — list + Nova (padrão Ações).
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  static const double _kSplit = 1100;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<ConversationGroup> _groups = const [];
  List<TenantUserModel> _users = const [];
  final Set<String> _selectedMembers = <String>{};

  bool _loading = true;
  String? _listError;
  String? _selectedId;
  bool _creating = false;
  bool _compactEditorOpen = false;
  bool _saving = false;
  bool _deleting = false;
  String? _editorError;
  String? _saveFeedback;
  ConversationGroup? _editing;

  bool get _editorOpen => _creating || _editing != null;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final tenantId = authService.tenantId ?? '';
      final results = await Future.wait([
        conversationGroupService.listGroups(),
        tenantId.isEmpty
            ? Future.value(<TenantUserModel>[])
            : tenantUserService.listUsers(tenantId),
      ]);
      if (!mounted) return;
      final groups = results[0] as List<ConversationGroup>;
      final users = results[1] as List<TenantUserModel>;
      setState(() {
        _groups = groups;
        _users = users;
        _loading = false;
        if (_selectedId != null &&
            !_creating &&
            !groups.any((g) => g.id == _selectedId)) {
          _clearEditor();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = 'Não foi possível carregar os grupos.';
      });
    }
  }

  void _clearEditor() {
    _selectedId = null;
    _creating = false;
    _editing = null;
    _compactEditorOpen = false;
    _saveFeedback = null;
    _editorError = null;
    _nameCtrl.clear();
    _descCtrl.clear();
    _selectedMembers.clear();
  }

  void _startCreate() {
    setState(() {
      _creating = true;
      _editing = null;
      _selectedId = null;
      _compactEditorOpen = true;
      _saveFeedback = null;
      _editorError = null;
      _nameCtrl.clear();
      _descCtrl.clear();
      _selectedMembers.clear();
    });
  }

  void _selectGroup(ConversationGroup group) {
    setState(() {
      _creating = false;
      _editing = group;
      _selectedId = group.id;
      _compactEditorOpen = true;
      _saveFeedback = null;
      _editorError = null;
      _nameCtrl.text = group.name;
      _descCtrl.text = group.description ?? '';
      _selectedMembers
        ..clear()
        ..addAll(group.memberUserIds);
    });
  }

  List<ConversationGroup> get _visible {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    return _groups.where((g) {
      return g.name.toLowerCase().contains(q) ||
          (g.description ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _editorError = 'Nome é obrigatório');
      return;
    }
    setState(() {
      _saving = true;
      _editorError = null;
      _saveFeedback = null;
    });
    try {
      if (_editing != null) {
        final updated = await conversationGroupService.updateGroup(
          id: _editing!.id,
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          memberUserIds: _selectedMembers.toList(),
        );
        if (!mounted) return;
        setState(() {
          _editing = updated;
          _selectedId = updated.id;
          _saveFeedback = 'Salvo';
        });
      } else {
        final created = await conversationGroupService.createGroup(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          memberUserIds: _selectedMembers.toList(),
        );
        if (!mounted) return;
        setState(() {
          _creating = false;
          _editing = created;
          _selectedId = created.id;
          _saveFeedback = 'Salvo';
        });
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _editorError = 'Erro ao salvar: $e';
        _saveFeedback = 'Falha ao salvar';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCurrent() async {
    final group = _editing;
    if (group == null || group.isDefault) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Excluir grupo', style: TextStyle(color: AppColors.text)),
        content: Text(
          'Excluir o grupo "${group.name}"?',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await conversationGroupService.deleteGroup(group.id);
      if (!mounted) return;
      setState(_clearEditor);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _editorError = 'Erro ao excluir: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = MediaQuery.sizeOf(context).width >= GroupsScreen._kSplit;
    final Widget body;
    if (split) {
      body = Row(
        children: [
          SizedBox(width: 300, child: _buildListPane()),
          Container(width: 1, color: AppColors.divider),
          Expanded(child: _buildEditorPane(showBack: false)),
        ],
      );
    } else if (_compactEditorOpen && _editorOpen) {
      body = _buildEditorPane(showBack: true);
    } else {
      body = _buildListPane();
    }
    return PremiumPageBackground(intensity: AmbientIntensity.soft, child: body);
  }

  Widget _buildListPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Grupos',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _startCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nova'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar grupo…',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(child: _buildListBody()),
      ],
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_listError!, style: const TextStyle(color: AppColors.text)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    final rows = _visible;
    if (rows.isEmpty) {
      return PremiumEmptyPanel(
        icon: Icons.groups_outlined,
        title: 'Nenhum grupo cadastrado',
        description: 'Use Nova para criar filas de atendimento (ex.: Comercial, Suporte).',
        accent: AppColors.primary,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final group = rows[index];
        final selected = !_creating && group.id == _selectedId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectGroup(group),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: AppMotion.hoverOf(context),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryMuted
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (group.isDefault)
                                const Text(
                                  'Padrão',
                                  style: TextStyle(
                                    color: AppColors.textSoft,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.memberCount} membro${group.memberCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditorPane({required bool showBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _compactEditorOpen = false;
                if (_creating) _clearEditor();
              }),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Voltar'),
            ),
          ),
        Expanded(child: _buildEditorBody()),
      ],
    );
  }

  Widget _buildEditorBody() {
    if (!_editorOpen) {
      return const Center(
        child: Text(
          'Selecione um grupo ou crie um novo.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _creating
                      ? 'Novo grupo'
                      : (_nameCtrl.text.trim().isEmpty
                          ? 'Editar grupo'
                          : _nameCtrl.text.trim()),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_editing != null && !_editing!.isDefault)
                OutlinedButton.icon(
                  onPressed: (_saving || _deleting) ? null : _deleteCurrent,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Excluir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                ),
              const SizedBox(width: 8),
              PremiumAccentButton(
                label: _saving ? 'Salvando…' : (_creating ? 'Criar' : 'Salvar'),
                icon: _saving ? null : Icons.save_rounded,
                onPressed: _saving ? null : _save,
                dense: true,
              ),
            ],
          ),
        ),
        if (_editorError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: AppColors.danger.withValues(alpha: 0.1),
            child: Text(
              _editorError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        if (_saveFeedback == 'Salvo')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppColors.success.withValues(alpha: 0.1),
            child: const Text(
              'Salvo',
              style: TextStyle(color: AppColors.success, fontSize: 12),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Nome *'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Membros',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_users.isEmpty)
                    const Text(
                      'Nenhum usuário da equipe carregado.',
                      style: TextStyle(color: AppColors.textSoft, fontSize: 12),
                    )
                  else
                    ..._users.map((user) {
                      final selected = _selectedMembers.contains(user.userId);
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedMembers.add(user.userId);
                            } else {
                              _selectedMembers.remove(user.userId);
                            }
                          });
                        },
                        title: Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : user.email,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          user.email,
                          style: const TextStyle(
                            color: AppColors.textSoft,
                            fontSize: 11,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
