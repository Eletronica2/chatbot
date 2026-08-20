import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/actions_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../widgets/premium_ui.dart';

const _kSurface = AppColors.surface;
const _kCard = AppColors.surfaceAlt;
const _kInput = AppColors.backgroundElevated;
const _kBorder = AppColors.border;
const _kText = AppColors.text;
const _kMuted = AppColors.textMuted;
const _kSubtle = AppColors.textSoft;
const _kAccent = AppColors.primary;
const _kOnAccent = AppColors.onPrimary;
const _kSuccess = AppColors.success;
const _kDanger = AppColors.danger;
const _kWarning = AppColors.warning;
const double _kSplit = 1100;

IconData _typeIcon(ActionType t) => switch (t) {
      ActionType.sendImage => Icons.image_outlined,
      ActionType.sendLink => Icons.link_rounded,
      ActionType.httpRequest => Icons.api_rounded,
      ActionType.delay => Icons.timer_outlined,
      ActionType.sendDocument => Icons.description_outlined,
    };

String _secondaryInfo(FlowAction action) {
  final c = action.config;
  return switch (action.actionType) {
    ActionType.sendImage => () {
        final caption = (c['caption'] as String?)?.trim() ?? '';
        if (caption.isNotEmpty) return caption;
        final w = c['width'];
        final h = c['height'];
        if (w != null && h != null) return '$w×$h';
        return 'Imagem cadastrada';
      }(),
    ActionType.sendLink => (c['url'] as String?)?.trim().isNotEmpty == true
        ? (c['url'] as String).trim()
        : ((c['title'] as String?)?.trim().isNotEmpty == true
            ? (c['title'] as String).trim()
            : 'Sem URL'),
    ActionType.httpRequest =>
      '${(c['method'] as String?)?.toUpperCase() ?? 'POST'} ${(c['url'] as String?)?.trim() ?? ''}'
          .trim(),
    ActionType.delay => '${c['seconds'] ?? 2} s',
    ActionType.sendDocument => () {
        final name = (c['filename'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) return name;
        return (c['url'] as String?)?.trim() ?? 'Documento';
      }(),
  };
}

// ── Main screen ──────────────────────────────────────────────────────────────

class ActionsScreen extends StatefulWidget {
  const ActionsScreen({super.key});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<FlowAction> _actions = const [];
  bool _loading = true;
  String? _listError;

  ActionType? _typeFilter;
  int? _selectedId;
  bool _creating = false;
  bool _compactEditorOpen = false;

  bool _saving = false;
  bool _deleting = false;
  String? _saveFeedback;
  String? _editorError;

  // Form state (shared create/edit)
  final _nameCtrl = TextEditingController();
  ActionType _selectedType = ActionType.sendImage;
  FlowAction? _editing;

  Uint8List? _imageBytes;
  String? _imageMime;
  String? _imageBase64;
  final _captionCtrl = TextEditingController();

  final _linkUrlCtrl = TextEditingController();
  final _linkTitleCtrl = TextEditingController();
  final _linkDescCtrl = TextEditingController();

  String _httpMethod = 'POST';
  final _httpUrlCtrl = TextEditingController();
  final _httpHeadersCtrl = TextEditingController(text: '{}');
  final _httpBodyCtrl = TextEditingController();

  final _delayCtrl = TextEditingController(text: '2');

  final _docUrlCtrl = TextEditingController();
  final _docFilenameCtrl = TextEditingController();

  bool get _isEdit => _editing != null;
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
    _captionCtrl.dispose();
    _linkUrlCtrl.dispose();
    _linkTitleCtrl.dispose();
    _linkDescCtrl.dispose();
    _httpUrlCtrl.dispose();
    _httpHeadersCtrl.dispose();
    _httpBodyCtrl.dispose();
    _delayCtrl.dispose();
    _docUrlCtrl.dispose();
    _docFilenameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final list = await actionsService.listActions();
      if (!mounted) return;
      setState(() {
        _actions = list;
        _loading = false;
        _listError = null;
        if (_selectedId != null &&
            !_creating &&
            !list.any((a) => a.id == _selectedId)) {
          _clearEditor();
        } else if (_editing != null) {
          final refreshed =
              list.where((a) => a.id == _editing!.id).firstOrNull;
          if (refreshed != null) {
            _editing = refreshed;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = 'Não foi possível carregar as ações.';
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
    _resetForm();
  }

  void _resetForm() {
    _nameCtrl.clear();
    _selectedType = ActionType.sendImage;
    _imageBytes = null;
    _imageMime = null;
    _imageBase64 = null;
    _captionCtrl.clear();
    _linkUrlCtrl.clear();
    _linkTitleCtrl.clear();
    _linkDescCtrl.clear();
    _httpMethod = 'POST';
    _httpUrlCtrl.clear();
    _httpHeadersCtrl.text = '{}';
    _httpBodyCtrl.clear();
    _delayCtrl.text = '2';
    _docUrlCtrl.clear();
    _docFilenameCtrl.clear();
  }

  void _loadFormFrom(FlowAction action) {
    _resetForm();
    _nameCtrl.text = action.name;
    _selectedType = action.actionType;
    final c = action.config;
    switch (action.actionType) {
      case ActionType.sendImage:
        _captionCtrl.text = c['caption'] as String? ?? '';
        _imageBase64 = c['image_data'] as String?;
        _imageMime = c['mime_type'] as String? ?? 'image/jpeg';
      case ActionType.sendLink:
        _linkUrlCtrl.text = c['url'] as String? ?? '';
        _linkTitleCtrl.text = c['title'] as String? ?? '';
        _linkDescCtrl.text = c['description'] as String? ?? '';
      case ActionType.httpRequest:
        _httpMethod = c['method'] as String? ?? 'POST';
        _httpUrlCtrl.text = c['url'] as String? ?? '';
        _httpHeadersCtrl.text = _jsonPretty(c['headers']);
        _httpBodyCtrl.text = c['body'] as String? ?? '';
      case ActionType.delay:
        _delayCtrl.text = '${c['seconds'] ?? 2}';
      case ActionType.sendDocument:
        _docUrlCtrl.text = c['url'] as String? ?? '';
        _docFilenameCtrl.text = c['filename'] as String? ?? '';
    }
  }

  String _jsonPretty(dynamic value) {
    if (value == null) return '{}';
    if (value is Map) {
      try {
        final entries =
            value.entries.map((e) => '  "${e.key}": "${e.value}"').join(',\n');
        return '{\n$entries\n}';
      } catch (_) {}
    }
    return value.toString();
  }

  void _startCreate() {
    setState(() {
      _creating = true;
      _editing = null;
      _selectedId = null;
      _compactEditorOpen = true;
      _saveFeedback = null;
      _editorError = null;
      _resetForm();
    });
  }

  void _selectAction(FlowAction action, {bool openCompact = true}) {
    setState(() {
      _creating = false;
      _editing = action;
      _selectedId = action.id;
      if (openCompact) _compactEditorOpen = true;
      _saveFeedback = null;
      _editorError = null;
      _loadFormFrom(action);
    });
  }

  void _onFormChanged() {
    if (_saveFeedback != null || _editorError != null) {
      setState(() {
        _saveFeedback = null;
        _editorError = null;
      });
    } else {
      setState(() {});
    }
  }

  List<FlowAction> get _visibleActions {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _actions.where((action) {
      if (_typeFilter != null && action.actionType != _typeFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final name = action.name.toLowerCase();
      final type = action.actionType.label.toLowerCase();
      final secondary = _secondaryInfo(action).toLowerCase();
      return name.contains(query) ||
          type.contains(query) ||
          secondary.contains(query);
    }).toList();
  }

  Map<String, dynamic>? _buildConfig() {
    return switch (_selectedType) {
      ActionType.sendImage => {
          if (_imageBase64 != null) 'image_data': _imageBase64!,
          'mime_type': _imageMime ?? 'image/jpeg',
          'caption': _captionCtrl.text.trim(),
        },
      ActionType.sendLink => {
          'url': _linkUrlCtrl.text.trim(),
          'title': _linkTitleCtrl.text.trim(),
          'description': _linkDescCtrl.text.trim(),
        },
      ActionType.httpRequest => {
          'method': _httpMethod,
          'url': _httpUrlCtrl.text.trim(),
          'headers': _parseJsonOrEmpty(_httpHeadersCtrl.text),
          'body': _httpBodyCtrl.text,
        },
      ActionType.delay => {
          'seconds': int.tryParse(_delayCtrl.text.trim()) ?? 2,
        },
      ActionType.sendDocument => {
          'url': _docUrlCtrl.text.trim(),
          'filename': _docFilenameCtrl.text.trim(),
        },
    };
  }

  dynamic _parseJsonOrEmpty(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return {};
      return _jsonStringToMap(trimmed);
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _jsonStringToMap(String text) {
    final result = <String, dynamic>{};
    final clean = text.replaceAll(RegExp(r'^\{|\}$'), '').trim();
    if (clean.isEmpty) return result;
    for (final pair in clean.split(',')) {
      final parts = pair.split(':');
      if (parts.length >= 2) {
        final key = parts[0].trim().replaceAll('"', '').replaceAll("'", '');
        final value = parts
            .sublist(1)
            .join(':')
            .trim()
            .replaceAll('"', '')
            .replaceAll("'", '');
        result[key] = value;
      }
    }
    return result;
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Nome é obrigatório';
    return switch (_selectedType) {
      ActionType.sendImage =>
        (_isEdit || _imageBase64 != null) ? null : 'Selecione uma imagem',
      ActionType.sendLink =>
        _linkUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
      ActionType.httpRequest =>
        _httpUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
      ActionType.delay => (int.tryParse(_delayCtrl.text) == null)
          ? 'Informe um número de segundos válido'
          : null,
      ActionType.sendDocument =>
        _docUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
    };
  }

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() {
        _editorError = validationError;
        _saveFeedback = validationError;
      });
      return;
    }
    setState(() {
      _saving = true;
      _editorError = null;
      _saveFeedback = null;
    });
    try {
      final config = _buildConfig() ?? {};
      if (_isEdit) {
        final updated = await actionsService.updateAction(
          id: _editing!.id,
          name: _nameCtrl.text.trim(),
          config: config,
        );
        if (!mounted) return;
        setState(() {
          _editing = updated;
          _selectedId = updated.id;
          _saveFeedback = 'Salva';
        });
      } else {
        final created = await actionsService.createAction(
          name: _nameCtrl.text.trim(),
          actionType: _selectedType,
          config: config,
        );
        if (!mounted) return;
        setState(() {
          _creating = false;
          _editing = created;
          _selectedId = created.id;
          _saveFeedback = 'Salva';
          _loadFormFrom(created);
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
    final action = _editing;
    if (action == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Excluir ação', style: TextStyle(color: _kText)),
        content: Text(
          'Deseja excluir a ação "${action.name}"?\n\n'
          'Automações que usam esta chave em hook.action deixarão de encontrá-la. '
          'Esta operação não pode ser desfeita.',
          style: const TextStyle(color: _kMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: _kMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await actionsService.deleteAction(action.id);
      if (!mounted) return;
      setState(_clearEditor);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _editorError = 'Erro ao excluir: $e';
        _saveFeedback = 'Falha ao excluir';
      });
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _imageBytes = file.bytes;
      _imageMime = _mimeFromExtension(file.extension ?? 'jpg');
      _imageBase64 = ActionsService.bytesToBase64(file.bytes!);
      _saveFeedback = null;
      _editorError = null;
    });
  }

  String _mimeFromExtension(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  @override
  Widget build(BuildContext context) {
    final split = MediaQuery.sizeOf(context).width >= _kSplit;
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

    return PremiumPageBackground(
      intensity: AmbientIntensity.soft,
      child: body,
    );
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
                      'Ações',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _startCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: _kOnAccent,
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
                style: const TextStyle(color: _kText, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nome ou tipo',
                  hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: _kMuted, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: _kInput,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PremiumFilterChip(
                    label: 'Todas',
                    selected: _typeFilter == null,
                    onTap: () => setState(() => _typeFilter = null),
                  ),
                  for (final type in ActionType.values)
                    PremiumFilterChip(
                      label: type.label,
                      icon: _typeIcon(type),
                      selected: _typeFilter == type,
                      onTap: () => setState(() => _typeFilter = type),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _kBorder),
        Expanded(child: _buildListBody()),
      ],
    );
  }

  Widget _buildListBody() {
    if (_loading) {
      return const _ActionsSkeleton();
    }
    if (_listError != null) {
      return _ActionsInlineError(message: _listError!, onRetry: _reload);
    }
    final rows = _visibleActions;
    if (rows.isEmpty) {
      final searching = _searchCtrl.text.trim().isNotEmpty || _typeFilter != null;
      return _buildPlaceholder(
        icon: searching ? Icons.search_off_rounded : Icons.bolt_outlined,
        title: searching
            ? 'Nenhuma ação encontrada'
            : 'Nenhuma ação cadastrada',
        message: searching
            ? 'Ajuste a busca ou o filtro. Eles usam apenas os dados já carregados.'
            : 'Use Nova para cadastrar imagens, links, documentos ou requisições reutilizáveis.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final action = rows[index];
        return _ActionListItem(
          action: action,
          selected: !_creating && action.id == _selectedId,
          onTap: () => _selectAction(action),
        );
      },
    );
  }

  Widget _buildEditorPane({required bool showBack}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _compactEditorOpen = false;
                  if (_creating) {
                    _creating = false;
                    _resetForm();
                  }
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Voltar'),
                style: TextButton.styleFrom(foregroundColor: _kText),
              ),
            ),
          ),
        Expanded(child: _buildEditorBody()),
      ],
    );
  }

  Widget _buildEditorBody() {
    if (!_editorOpen) {
      return _buildPlaceholder(
        icon: Icons.bolt_outlined,
        title: 'Selecione uma ação',
        message:
            'Escolha uma ação à esquerda para ver a configuração, ou crie uma nova.',
      );
    }
    return _ActionEditorForm(
      isCreating: _creating,
      isEdit: _isEdit,
      saving: _saving,
      deleting: _deleting,
      saveFeedback: _saveFeedback,
      editorError: _editorError,
      nameCtrl: _nameCtrl,
      selectedType: _selectedType,
      originalName: _editing?.name,
      onTypeChanged: (type) {
        if (_isEdit) return;
        setState(() {
          _selectedType = type;
          _saveFeedback = null;
          _editorError = null;
        });
      },
      onChanged: _onFormChanged,
      onSave: _save,
      onDelete: _isEdit ? _deleteCurrent : null,
      imageBytes: _imageBytes,
      imageBase64: _imageBase64,
      onPickImage: _pickImage,
      captionCtrl: _captionCtrl,
      linkUrlCtrl: _linkUrlCtrl,
      linkTitleCtrl: _linkTitleCtrl,
      linkDescCtrl: _linkDescCtrl,
      httpMethod: _httpMethod,
      onHttpMethodChanged: (v) {
        setState(() {
          _httpMethod = v;
          _saveFeedback = null;
        });
      },
      httpUrlCtrl: _httpUrlCtrl,
      httpHeadersCtrl: _httpHeadersCtrl,
      httpBodyCtrl: _httpBodyCtrl,
      delayCtrl: _delayCtrl,
      docUrlCtrl: _docUrlCtrl,
      docFilenameCtrl: _docFilenameCtrl,
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kCard,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder),
              ),
              child: Icon(icon, size: 28, color: _kAccent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ── List item ────────────────────────────────────────────────────────────────

class _ActionListItem extends StatefulWidget {
  const _ActionListItem({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final FlowAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ActionListItem> createState() => _ActionListItemState();
}

class _ActionListItemState extends State<_ActionListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: AppMotion.hoverOf(context),
              curve: AppMotion.hoverCurve,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: widget.selected
                    ? AppColors.primaryMuted
                    : (_hovered ? AppColors.surfaceSoft : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.selected
                      ? _kAccent.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Icon(
                      _typeIcon(action.actionType),
                      size: 16,
                      color: _kAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _kText,
                            fontSize: 13,
                            fontWeight: widget.selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          action.actionType.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kMuted, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _secondaryInfo(action),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kSubtle, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Editor form ──────────────────────────────────────────────────────────────

class _ActionEditorForm extends StatelessWidget {
  const _ActionEditorForm({
    required this.isCreating,
    required this.isEdit,
    required this.saving,
    required this.deleting,
    required this.saveFeedback,
    required this.editorError,
    required this.nameCtrl,
    required this.selectedType,
    required this.originalName,
    required this.onTypeChanged,
    required this.onChanged,
    required this.onSave,
    required this.onDelete,
    required this.imageBytes,
    required this.imageBase64,
    required this.onPickImage,
    required this.captionCtrl,
    required this.linkUrlCtrl,
    required this.linkTitleCtrl,
    required this.linkDescCtrl,
    required this.httpMethod,
    required this.onHttpMethodChanged,
    required this.httpUrlCtrl,
    required this.httpHeadersCtrl,
    required this.httpBodyCtrl,
    required this.delayCtrl,
    required this.docUrlCtrl,
    required this.docFilenameCtrl,
  });

  final bool isCreating;
  final bool isEdit;
  final bool saving;
  final bool deleting;
  final String? saveFeedback;
  final String? editorError;
  final TextEditingController nameCtrl;
  final ActionType selectedType;
  final String? originalName;
  final ValueChanged<ActionType> onTypeChanged;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final Uint8List? imageBytes;
  final String? imageBase64;
  final VoidCallback onPickImage;
  final TextEditingController captionCtrl;
  final TextEditingController linkUrlCtrl;
  final TextEditingController linkTitleCtrl;
  final TextEditingController linkDescCtrl;
  final String httpMethod;
  final ValueChanged<String> onHttpMethodChanged;
  final TextEditingController httpUrlCtrl;
  final TextEditingController httpHeadersCtrl;
  final TextEditingController httpBodyCtrl;
  final TextEditingController delayCtrl;
  final TextEditingController docUrlCtrl;
  final TextEditingController docFilenameCtrl;

  @override
  Widget build(BuildContext context) {
    final nameChanged =
        isEdit && originalName != null && nameCtrl.text.trim() != originalName;
    final feedbackColor =
        saveFeedback == 'Salva' ? _kSuccess : _kDanger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: const BoxDecoration(
            color: _kSurface,
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final title = Text(
                isCreating ? 'Nova ação' : nameCtrl.text.trim().isEmpty
                    ? 'Editar ação'
                    : nameCtrl.text.trim(),
                style: const TextStyle(
                  color: _kText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              final meta = Row(
                children: [
                  Icon(_typeIcon(selectedType), size: 14, color: _kAccent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      selectedType.label,
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (saveFeedback != null && saveFeedback!.isNotEmpty)
                    Text(
                      saveFeedback!,
                      style: TextStyle(
                        color: feedbackColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (onDelete != null)
                    OutlinedButton.icon(
                      onPressed: (saving || deleting) ? null : onDelete,
                      icon: deleting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Excluir'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kDanger,
                        side: BorderSide(color: _kDanger.withValues(alpha: 0.45)),
                      ),
                    ),
                  PremiumAccentButton(
                    label: saving
                        ? 'Salvando...'
                        : (isCreating ? 'Criar' : 'Salvar'),
                    icon: saving ? null : Icons.save_rounded,
                    onPressed: saving ? null : onSave,
                    dense: true,
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 6),
                    meta,
                    const SizedBox(height: 10),
                    actions,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 4),
                        meta,
                      ],
                    ),
                  ),
                  actions,
                ],
              );
            },
          ),
        ),
        if (editorError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: _kDanger.withValues(alpha: 0.1),
            child: Text(
              editorError!,
              style: const TextStyle(color: _kDanger, fontSize: 13),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LabeledField(
                    label: 'Nome (chave nas Automações) *',
                    child: _DarkField(
                      controller: nameCtrl,
                      hint: 'Ex: Imagem de boas-vindas',
                      onChanged: onChanged,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Automações referenciam esta ação pelo nome em hook.action.',
                    style: TextStyle(color: _kSubtle, fontSize: 11, height: 1.4),
                  ),
                  if (nameChanged) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kWarning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _kWarning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'Alterar o nome pode quebrar etapas que já usam a chave anterior.',
                        style: TextStyle(
                          color: _kWarning,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (isCreating) ...[
                    const Text(
                      'Tipo *',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ActionType.values.map((t) {
                        final selected = selectedType == t;
                        return Semantics(
                          button: true,
                          label: 'Tipo ${t.label}',
                          child: GestureDetector(
                            onTap: () => onTypeChanged(t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _kAccent.withValues(alpha: 0.14)
                                    : _kInput,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? _kAccent : _kBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _typeIcon(t),
                                    size: 14,
                                    color: selected ? _kAccent : _kSubtle,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    t.label,
                                    style: TextStyle(
                                      color: selected ? _kText : _kMuted,
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kInput,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(_typeIcon(selectedType),
                              size: 16, color: _kAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Tipo: ${selectedType.label}',
                            style: const TextStyle(
                              color: _kText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Não alterável',
                            style: TextStyle(color: _kSubtle, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _buildTypeFields(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFields() {
    return switch (selectedType) {
      ActionType.sendImage => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Imagem',
              style: TextStyle(
                color: _kMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (imageBytes != null)
              Container(
                height: 140,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                  image: DecorationImage(
                    image: MemoryImage(imageBytes!),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else if (isEdit && imageBase64 != null)
              Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _kSuccess.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _kSuccess.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.centerLeft,
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: _kSuccess, size: 14),
                    SizedBox(width: 8),
                    Text(
                      'Imagem já cadastrada',
                      style: TextStyle(color: _kSuccess, fontSize: 12),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: onPickImage,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: Text(
                imageBase64 != null ? 'Trocar imagem' : 'Selecionar imagem',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAccent,
                side: const BorderSide(color: _kBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Máx. 1280px — convertida para JPEG pelo servidor',
              style: TextStyle(color: _kSubtle, fontSize: 11),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Legenda (opcional)',
              child: _DarkField(
                controller: captionCtrl,
                hint: 'Texto que acompanha a imagem',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ActionType.sendLink => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(
              label: 'URL *',
              child: _DarkField(
                controller: linkUrlCtrl,
                hint: 'https://exemplo.com',
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Título',
              child: _DarkField(
                controller: linkTitleCtrl,
                hint: 'Título do link',
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Descrição',
              child: _DarkField(
                controller: linkDescCtrl,
                hint: 'Breve descrição do link',
                maxLines: 3,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ActionType.httpRequest => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 480;
                final method = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Método *',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _kInput,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: httpMethod,
                          isExpanded: true,
                          dropdownColor: _kCard,
                          style: const TextStyle(color: _kText, fontSize: 13),
                          items: const [
                            'GET',
                            'POST',
                            'PUT',
                            'PATCH',
                            'DELETE',
                          ]
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) onHttpMethodChanged(v);
                          },
                        ),
                      ),
                    ),
                  ],
                );
                final url = _LabeledField(
                  label: 'URL *',
                  child: _DarkField(
                    controller: httpUrlCtrl,
                    hint: 'https://api.exemplo.com/endpoint',
                    onChanged: onChanged,
                  ),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      method,
                      const SizedBox(height: 14),
                      url,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: method),
                    const SizedBox(width: 12),
                    Expanded(child: url),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Headers (JSON)',
              child: _DarkField(
                controller: httpHeadersCtrl,
                hint: '{"Authorization": "Bearer ..."}',
                maxLines: 3,
                monospace: true,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Evite colar tokens reais em ambientes compartilhados. O valor é armazenado no config da ação.',
              style: TextStyle(color: _kSubtle, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Body',
              child: _DarkField(
                controller: httpBodyCtrl,
                hint: '{"key": "value"}',
                maxLines: 4,
                monospace: true,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ActionType.delay => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(
              label: 'Aguardar (segundos) *',
              child: _DarkField(
                controller: delayCtrl,
                hint: '2',
                keyboardType: TextInputType.number,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'O bot aguardará este tempo antes de continuar o fluxo.',
              style: TextStyle(color: _kSubtle, fontSize: 12),
            ),
          ],
        ),
      ActionType.sendDocument => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledField(
              label: 'URL do documento *',
              child: _DarkField(
                controller: docUrlCtrl,
                hint: 'https://exemplo.com/arquivo.pdf',
                onChanged: onChanged,
              ),
            ),
            const SizedBox(height: 14),
            _LabeledField(
              label: 'Nome do arquivo',
              child: _DarkField(
                controller: docFilenameCtrl,
                hint: 'cardapio.pdf',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
    };
  }
}

// ── Shared fields ────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.monospace = false,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool monospace;
  final TextInputType? keyboardType;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => onChanged?.call(),
      style: TextStyle(
        color: _kText,
        fontSize: 13,
        fontFamily: monospace ? 'monospace' : null,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSubtle),
        filled: true,
        fillColor: _kInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }
}

class _ActionsInlineError extends StatelessWidget {
  const _ActionsInlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kDanger, size: 28),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kText, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsSkeleton extends StatelessWidget {
  const _ActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
