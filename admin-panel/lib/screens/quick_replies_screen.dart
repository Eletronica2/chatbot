import 'package:flutter/material.dart';

import '../models/quick_reply.dart';
import '../services/quick_reply_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

/// Respostas rápidas do usuário — list + Nova.
class QuickRepliesScreen extends StatefulWidget {
  const QuickRepliesScreen({super.key});

  static const double _kSplit = 1100;

  @override
  State<QuickRepliesScreen> createState() => _QuickRepliesScreenState();
}

class _QuickRepliesScreenState extends State<QuickRepliesScreen> {
  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _shortcutCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  List<QuickReply> _items = const [];
  bool _loading = true;
  String? _listError;
  String? _selectedId;
  bool _creating = false;
  bool _compactEditorOpen = false;
  bool _saving = false;
  bool _deleting = false;
  String? _editorError;
  QuickReply? _editing;

  bool get _editorOpen => _creating || _editing != null;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _shortcutCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final list = await quickReplyService.listQuickReplies();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        if (_selectedId != null &&
            !_creating &&
            !list.any((item) => item.id == _selectedId)) {
          _clearEditor();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = 'Não foi possível carregar as respostas rápidas.';
      });
    }
  }

  void _clearEditor() {
    _selectedId = null;
    _creating = false;
    _editing = null;
    _compactEditorOpen = false;
    _editorError = null;
    _titleCtrl.clear();
    _shortcutCtrl.clear();
    _contentCtrl.clear();
  }

  void _startCreate() {
    setState(() {
      _creating = true;
      _editing = null;
      _selectedId = null;
      _compactEditorOpen = true;
        _editorError = null;
      _titleCtrl.clear();
      _shortcutCtrl.clear();
      _contentCtrl.clear();
    });
  }

  void _selectItem(QuickReply item) {
    setState(() {
      _creating = false;
      _editing = item;
      _selectedId = item.id;
      _compactEditorOpen = true;
        _editorError = null;
      _titleCtrl.text = item.title;
      _shortcutCtrl.text = item.bareShortcut;
      _contentCtrl.text = item.content;
    });
  }

  List<QuickReply> get _visible {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      return item.title.toLowerCase().contains(q) ||
          item.shortcut.toLowerCase().contains(q) ||
          item.content.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _editorError = 'Título é obrigatório');
      return;
    }
    if (_shortcutCtrl.text.trim().isEmpty) {
      setState(() => _editorError = 'Atalho é obrigatório (ex.: oi)');
      return;
    }
    if (_contentCtrl.text.trim().isEmpty) {
      setState(() => _editorError = 'Conteúdo é obrigatório');
      return;
    }
    setState(() {
      _saving = true;
      _editorError = null;
    });
    try {
      if (_editing != null) {
        final updated = await quickReplyService.updateQuickReply(
          id: _editing!.id,
          title: _titleCtrl.text.trim(),
          shortcut: _shortcutCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _editing = updated;
          _selectedId = updated.id;
        });
      } else {
        final created = await quickReplyService.createQuickReply(
          title: _titleCtrl.text.trim(),
          shortcut: _shortcutCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _creating = false;
          _editing = created;
          _selectedId = created.id;
        });
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _editorError = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCurrent() async {
    final item = _editing;
    if (item == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Excluir resposta', style: TextStyle(color: AppColors.text)),
        content: Text(
          'Excluir "${item.title}"?',
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
      await quickReplyService.deleteQuickReply(item.id);
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
    final split =
        MediaQuery.sizeOf(context).width >= QuickRepliesScreen._kSplit;
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
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Respostas rápidas',
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
                  hintText: 'Buscar por título ou atalho…',
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_listError!, style: const TextStyle(color: AppColors.text)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _reload, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    final rows = _visible;
    if (rows.isEmpty) {
      return const PremiumEmptyPanel(
        icon: Icons.flash_on_outlined,
        title: 'Nenhuma resposta rápida',
        description:
            'Crie atalhos como /oi para inserir texto no compositor (sem enviar).',
        accent: AppColors.primary,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final item = rows[index];
        final selected = !_creating && item.id == _selectedId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectItem(item),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: AppMotion.hoverOf(context),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryMuted : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '/${item.bareShortcut}',
                      style: const TextStyle(
                        color: AppColors.primarySoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
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
          'Selecione uma resposta ou crie uma nova.',
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
                  _creating ? 'Nova resposta rápida' : 'Editar resposta',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_editing != null)
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: AppColors.danger.withValues(alpha: 0.1),
            child: Text(
              _editorError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
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
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Título *'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _shortcutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Atalho *',
                      helperText: 'Digite sem / — no chat use /atalho',
                      prefixText: '/',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Conteúdo *',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
