import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/actions_service.dart';

// ── Colors (shared with admin panel theme) ──────────────────────────────────

const _kBg = Color(0xFF0B0F1A);
const _kSurface = Color(0xFF121826);
const _kCard = Color(0xFF182133);
const _kBorder = Color(0xFF25304A);
const _kText = Color(0xFFF5F7FF);
const _kMuted = Color(0xFF98A4C0);
const _kSubtle = Color(0xFF6E7B99);
const _kAccent = Color(0xFF7C8CFF);
const _kSuccess = Color(0xFF10B981);
const _kDanger = Color(0xFFEF4444);

// ── Action type presentation helpers ────────────────────────────────────────

Color _typeColor(ActionType t) => switch (t) {
      ActionType.sendImage => const Color(0xFF8B5CF6),
      ActionType.sendLink => const Color(0xFF0EA5E9),
      ActionType.httpRequest => const Color(0xFF10B981),
      ActionType.delay => const Color(0xFFF59E0B),
      ActionType.sendDocument => const Color(0xFFEC4899),
    };

IconData _typeIcon(ActionType t) => switch (t) {
      ActionType.sendImage => Icons.image_rounded,
      ActionType.sendLink => Icons.link_rounded,
      ActionType.httpRequest => Icons.http_rounded,
      ActionType.delay => Icons.timer_rounded,
      ActionType.sendDocument => Icons.attach_file_rounded,
    };

// ── Main screen ──────────────────────────────────────────────────────────────

class ActionsScreen extends StatefulWidget {
  const ActionsScreen({super.key});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  late Future<List<FlowAction>> _future;

  @override
  void initState() {
    super.initState();
    _future = actionsService.listActions();
  }

  void _reload() {
    setState(() => _future = actionsService.listActions());
  }

  // ── Open create/edit dialog ───────────────────────────────────────────────

  Future<void> _openDialog({FlowAction? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ActionDialog(existing: existing),
    );
    if (saved == true) _reload();
  }

  Future<void> _deleteAction(FlowAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Excluir ação', style: TextStyle(color: _kText)),
        content: Text(
          'Deseja excluir a ação "${action.name}"? Esta operação não pode ser desfeita.',
          style: const TextStyle(color: _kMuted),
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
    try {
      await actionsService.deleteAction(action.id);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: _kDanger),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: FutureBuilder<List<FlowAction>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _kAccent));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Erro: ${snap.error}', style: const TextStyle(color: _kDanger)),
                  );
                }
                final actions = snap.data ?? [];
                if (actions.isEmpty) return _buildEmpty();
                return _buildList(actions);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt_rounded, color: _kAccent, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ações', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('Gerencie ações reutilizáveis para seus fluxos', style: TextStyle(color: _kMuted, fontSize: 13)),
            ],
          ),
          const Spacer(),
          _PrimaryBtn(
            label: 'Nova ação',
            icon: Icons.add_rounded,
            onTap: () => _openDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, color: _kAccent, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('Nenhuma ação cadastrada', style: TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Crie ações reutilizáveis como envio de imagens, links ou requisições HTTP.',
              style: TextStyle(color: _kMuted, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          _PrimaryBtn(label: 'Criar primeira ação', icon: Icons.add_rounded, onTap: () => _openDialog()),
        ],
      ),
    );
  }

  Widget _buildList(List<FlowAction> actions) {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: actions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _ActionCard(
        action: actions[i],
        onEdit: () => _openDialog(existing: actions[i]),
        onDelete: () => _deleteAction(actions[i]),
      ),
    );
  }
}

// ── Action card ──────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.onEdit, required this.onDelete});
  final FlowAction action;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(action.actionType);
    final icon = _typeIcon(action.actionType);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.name, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    action.actionType.label,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18, color: _kMuted),
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _kDanger),
            tooltip: 'Excluir',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Create / Edit dialog ─────────────────────────────────────────────────────

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({this.existing});
  final FlowAction? existing;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _nameCtrl = TextEditingController();
  ActionType _selectedType = ActionType.sendImage;
  bool _saving = false;
  String? _error;

  // ── send_image ───────────────────────────────────────────────────────────
  Uint8List? _imageBytes;
  String? _imageMime;
  String? _imageBase64;
  final _captionCtrl = TextEditingController();

  // ── send_link ────────────────────────────────────────────────────────────
  final _linkUrlCtrl = TextEditingController();
  final _linkTitleCtrl = TextEditingController();
  final _linkDescCtrl = TextEditingController();

  // ── http_request ─────────────────────────────────────────────────────────
  String _httpMethod = 'POST';
  final _httpUrlCtrl = TextEditingController();
  final _httpHeadersCtrl = TextEditingController(text: '{}');
  final _httpBodyCtrl = TextEditingController(text: '');

  // ── delay ────────────────────────────────────────────────────────────────
  final _delayCtrl = TextEditingController(text: '2');

  // ── send_document ────────────────────────────────────────────────────────
  final _docUrlCtrl = TextEditingController();
  final _docFilenameCtrl = TextEditingController();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _selectedType = e.actionType;
      final c = e.config;
      switch (e.actionType) {
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
  }

  String _jsonPretty(dynamic value) {
    if (value == null) return '{}';
    if (value is Map) {
      try {
        final entries = value.entries.map((e) => '  "${e.key}": "${e.value}"').join(',\n');
        return '{\n$entries\n}';
      } catch (_) {}
    }
    return value.toString();
  }

  @override
  void dispose() {
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

  // ── File picker ───────────────────────────────────────────────────────────

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
    });
  }

  String _mimeFromExtension(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  // ── Build config from fields ──────────────────────────────────────────────

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
      // Basic JSON parse via Dart — accept only objects
      final trimmed = text.trim();
      if (trimmed.isEmpty) return {};
      // We'll send it as a string and let backend handle; but try to validate
      return _jsonStringToMap(trimmed);
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _jsonStringToMap(String text) {
    // Simple key-value extraction from JSON string
    final result = <String, dynamic>{};
    final clean = text.replaceAll(RegExp(r'^\{|\}$'), '').trim();
    if (clean.isEmpty) return result;
    for (final pair in clean.split(',')) {
      final parts = pair.split(':');
      if (parts.length >= 2) {
        final key = parts[0].trim().replaceAll('"', '').replaceAll("'", '');
        final value = parts.sublist(1).join(':').trim().replaceAll('"', '').replaceAll("'", '');
        result[key] = value;
      }
    }
    return result;
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Nome é obrigatório';
    return switch (_selectedType) {
      ActionType.sendImage => (_isEdit || _imageBase64 != null) ? null : 'Selecione uma imagem',
      ActionType.sendLink => _linkUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
      ActionType.httpRequest => _httpUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
      ActionType.delay => (int.tryParse(_delayCtrl.text) == null) ? 'Informe um número de segundos válido' : null,
      ActionType.sendDocument => _docUrlCtrl.text.trim().isEmpty ? 'URL é obrigatória' : null,
    };
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = _buildConfig() ?? {};
      if (_isEdit) {
        await actionsService.updateAction(
          id: widget.existing!.id,
          name: _nameCtrl.text.trim(),
          config: config,
        );
      } else {
        await actionsService.createAction(
          name: _nameCtrl.text.trim(),
          actionType: _selectedType,
          config: config,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildNameField(),
                    const SizedBox(height: 16),
                    if (!_isEdit) _buildTypeSelector(),
                    if (!_isEdit) const SizedBox(height: 16),
                    _buildTypeFields(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kDanger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kDanger.withOpacity(0.3)),
                        ),
                        child: Text(_error!, style: const TextStyle(color: _kDanger, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded, color: _kAccent, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            _isEdit ? 'Editar ação' : 'Nova ação',
            style: const TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _kMuted, size: 20),
            onPressed: _saving ? null : () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nome da ação *', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _nameCtrl, hint: 'Ex: Imagem de boas-vindas'),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tipo *', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ActionType.values.map((t) {
            final selected = _selectedType == t;
            final color = _typeColor(t);
            return GestureDetector(
              onTap: () => setState(() => _selectedType = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.15) : _kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? color : _kBorder,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_typeIcon(t), size: 14, color: selected ? color : _kSubtle),
                    const SizedBox(width: 6),
                    Text(
                      t.label,
                      style: TextStyle(
                        color: selected ? color : _kMuted,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTypeFields() {
    return switch (_selectedType) {
      ActionType.sendImage => _buildImageFields(),
      ActionType.sendLink => _buildLinkFields(),
      ActionType.httpRequest => _buildHttpFields(),
      ActionType.delay => _buildDelayFields(),
      ActionType.sendDocument => _buildDocumentFields(),
    };
  }

  // ── Image fields ──────────────────────────────────────────────────────────

  Widget _buildImageFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Imagem', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_imageBytes != null)
          Container(
            height: 120,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
              image: DecorationImage(image: MemoryImage(_imageBytes!), fit: BoxFit.cover),
            ),
          )
        else if (_isEdit && _imageBase64 != null)
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _kSuccess.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kSuccess.withOpacity(0.3)),
            ),
            alignment: Alignment.centerLeft,
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: _kSuccess, size: 14),
                SizedBox(width: 8),
                Text('Imagem já cadastrada', style: TextStyle(color: _kSuccess, fontSize: 12)),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _picking ? null : _pickImage,
          icon: const Icon(Icons.upload_rounded, size: 16),
          label: Text(_imageBase64 != null ? 'Trocar imagem' : 'Selecionar imagem'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kAccent,
            side: const BorderSide(color: _kBorder),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Máx. 1280px — convertida para JPEG pelo servidor',
            style: TextStyle(color: _kSubtle, fontSize: 11)),
        const SizedBox(height: 14),
        const Text('Legenda (opcional)', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _captionCtrl, hint: 'Texto que acompanha a imagem'),
      ],
    );
  }

  bool get _picking => false; // picker is synchronous; kept for API symmetry

  // ── Link fields ───────────────────────────────────────────────────────────

  Widget _buildLinkFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('URL *', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _linkUrlCtrl, hint: 'https://exemplo.com'),
        const SizedBox(height: 14),
        const Text('Título', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _linkTitleCtrl, hint: 'Título do link'),
        const SizedBox(height: 14),
        const Text('Descrição', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _linkDescCtrl, hint: 'Breve descrição do link', maxLines: 3),
      ],
    );
  }

  // ── HTTP request fields ───────────────────────────────────────────────────

  Widget _buildHttpFields() {
    const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Método *', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _httpMethod,
                    dropdownColor: _kCard,
                    style: const TextStyle(color: _kText, fontSize: 13),
                    borderRadius: BorderRadius.circular(8),
                    items: methods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _httpMethod = v ?? 'POST'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('URL *', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _TextField(controller: _httpUrlCtrl, hint: 'https://api.exemplo.com/endpoint'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Headers (JSON)', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _httpHeadersCtrl, hint: '{"Authorization": "Bearer ..."}', maxLines: 3, monospace: true),
        const SizedBox(height: 14),
        const Text('Body', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _httpBodyCtrl, hint: '{"key": "value"}', maxLines: 4, monospace: true),
      ],
    );
  }

  // ── Delay fields ──────────────────────────────────────────────────────────

  Widget _buildDelayFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Aguardar (segundos) *',
            style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(
          width: 160,
          child: _TextField(
            controller: _delayCtrl,
            hint: '2',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 6),
        const Text('O bot aguardará este tempo antes de continuar o fluxo.',
            style: TextStyle(color: _kSubtle, fontSize: 12)),
      ],
    );
  }

  // ── Document fields ───────────────────────────────────────────────────────

  Widget _buildDocumentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('URL do documento *',
            style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _docUrlCtrl, hint: 'https://exemplo.com/arquivo.pdf'),
        const SizedBox(height: 14),
        const Text('Nome do arquivo', style: TextStyle(color: _kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        _TextField(controller: _docFilenameCtrl, hint: 'cardapio.pdf'),
      ],
    );
  }

  // ── Dialog footer ─────────────────────────────────────────────────────────

  Widget _buildDialogFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _kBorder))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _kMuted)),
          ),
          const SizedBox(width: 12),
          _PrimaryBtn(
            label: _isEdit ? 'Salvar' : 'Criar ação',
            onTap: _saving ? null : _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────────

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.monospace = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool monospace;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        color: _kText,
        fontSize: 13,
        fontFamily: monospace ? 'monospace' : null,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSubtle),
        filled: true,
        fillColor: _kSurface,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
    );
  }
}
