import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import '../services/flow_admin_service.dart';
import '../services/tenant_service.dart';

// ── Dark palette ────────────────────────────────────────────────
const _kBg      = Color(0xFF0B1120);
const _kSurface = Color(0xFF111827);
const _kCard    = Color(0xFF1E293B);
const _kCardHdr = Color(0xFF243044);
const _kInput   = Color(0xFF192236);
const _kBorder  = Color(0xFF334155);
const _kText    = Color(0xFFE2E8F0);
const _kMuted   = Color(0xFF94A3B8);
const _kSubtle  = Color(0xFF64748B);
const _kAccent  = Color(0xFF4F46E5);
const _kSuccess = Color(0xFF10B981);
const _kDanger  = Color(0xFFEF4444);

// ── Draft data models ────────────────────────────────────────────
class _OptionDraft {
  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  _OptionDraft({String label = '', String value = ''})
      : labelCtrl = TextEditingController(text: label),
        valueCtrl = TextEditingController(text: value);
  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _TransitionDraft {
  final TextEditingController keywordCtrl;
  String targetState;
  _TransitionDraft({String keyword = '', this.targetState = ''})
      : keywordCtrl = TextEditingController(text: keyword);
  void dispose() => keywordCtrl.dispose();
}

class _StateDraft {
  final TextEditingController nameCtrl;
  final TextEditingController msgCtrl;
  final List<_OptionDraft> options;
  final List<_TransitionDraft> transitions;
  bool expanded;

  _StateDraft({
    String name = '',
    String message = '',
    List<_OptionDraft>? options,
    List<_TransitionDraft>? transitions,
    this.expanded = false,
  })  : nameCtrl = TextEditingController(text: name),
        msgCtrl = TextEditingController(text: message),
        options = options ?? [],
        transitions = transitions ?? [];

  String get name => nameCtrl.text.trim();
  String get message => msgCtrl.text.trim();

  void dispose() {
    nameCtrl.dispose();
    msgCtrl.dispose();
    for (final o in options) o.dispose();
    for (final t in transitions) t.dispose();
  }
}

class _FlowDraft {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  String startState;
  final List<_StateDraft> states;

  _FlowDraft({
    required String name,
    String description = '',
    this.startState = '',
    List<_StateDraft>? states,
  })  : nameCtrl = TextEditingController(text: name),
        descCtrl = TextEditingController(text: description),
        states = states ?? [];

  String get name => nameCtrl.text.trim();
  String get description => descCtrl.text.trim();
  List<String> get stateNames =>
      states.map((s) => s.name).where((n) => n.isNotEmpty).toList();

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    for (final s in states) s.dispose();
  }
}

// ── Main screen ──────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<FlowSummaryModel> _flows = [];
  bool _loadingFlows = true;
  String? _selectedName;
  _FlowDraft? _draft;
  bool _loadingDraft = false;
  bool _saving = false;
  bool _aiEnabled = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await tenantService.fetchTenantSettings('default');
      if (mounted) setState(() => _aiEnabled = s.aiEnabled);
    } catch (_) {}
    await _reloadFlows();
  }

  Future<void> _reloadFlows() async {
    setState(() => _loadingFlows = true);
    try {
      final flows = await flowAdminService.listFlows();
      if (mounted) setState(() { _flows = flows; _loadingFlows = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFlows = false);
    }
  }

  Future<void> _selectFlow(String name) async {
    setState(() {
      _selectedName = name;
      _loadingDraft = true;
      _draft?.dispose();
      _draft = null;
    });
    try {
      final yaml = await flowAdminService.getFlowYaml(name);
      final draft = _parseYaml(name, yaml);
      if (mounted) setState(() { _draft = draft; _loadingDraft = false; });
    } catch (e) {
      if (mounted) { setState(() => _loadingDraft = false); _showErr('Erro ao carregar fluxo: $e'); }
    }
  }

  // ── YAML ↔ Draft ────────────────────────────────────────────────
  _FlowDraft _parseYaml(String fallback, String src) {
    try {
      final doc = loadYaml(src);
      if (doc is! Map) return _FlowDraft(name: fallback);
      final data = doc;
      final name        = data['name']?.toString() ?? fallback;
      final description = data['description']?.toString() ?? '';
      final startState  = (data['start_state'] ?? data['start'])?.toString() ?? '';
      final statesMap   = data['states'];
      final states = <_StateDraft>[];
      if (statesMap is Map) {
        for (final entry in statesMap.entries) {
          final sName = entry.key.toString();
          final sData = (entry.value is Map) ? entry.value as Map : <dynamic, dynamic>{};
          final msg   = sData['message']?.toString() ?? '';
          final opts  = <_OptionDraft>[];
          final rawOpts = sData['options'];
          if (rawOpts is List) {
            for (final o in rawOpts) {
              if (o is! Map) continue;
              final lbl = (o['label'] ?? o['text'])?.toString() ?? '';
              final val = (o['value'] ?? o['id'] ?? lbl)?.toString() ?? '';
              opts.add(_OptionDraft(label: lbl, value: val));
            }
          }
          final trans    = <_TransitionDraft>[];
          final rawTrans = sData['transitions'];
          if (rawTrans is List) {
            for (final t in rawTrans) {
              if (t is! Map) continue;
              final cond   = t['condition']?.toString() ?? '';
              final target = (t['target_state'] ?? t['target'] ?? t['next_state'] ?? t['next'])?.toString() ?? '';
              final kw     = cond.startsWith('contains:') ? cond.substring(9) : cond;
              trans.add(_TransitionDraft(keyword: kw, targetState: target));
            }
          }
          states.add(_StateDraft(name: sName, message: msg, options: opts, transitions: trans));
        }
      }
      return _FlowDraft(
        name: name,
        description: description,
        startState: startState.isEmpty && states.isNotEmpty ? states.first.name : startState,
        states: states,
      );
    } catch (_) {
      return _FlowDraft(name: fallback);
    }
  }

  String _toYaml(_FlowDraft d) {
    final b = StringBuffer();
    final start = d.startState.isNotEmpty
        ? d.startState
        : (d.states.isNotEmpty ? d.states.first.name : '');
    b.writeln('name: ${d.name}');
    if (d.description.isNotEmpty) b.writeln('description: "${_esc(d.description)}"');
    b.writeln('start_state: $start');
    b.writeln('states:');
    for (final s in d.states) {
      if (s.name.isEmpty) continue;
      b.writeln('  ${s.name}:');
      if (s.message.isNotEmpty) b.writeln('    message: "${_esc(s.message)}"');
      final opts = s.options.where((o) => o.labelCtrl.text.trim().isNotEmpty).toList();
      if (opts.isNotEmpty) {
        b.writeln('    options:');
        for (final o in opts) {
          b.writeln('      - label: "${_esc(o.labelCtrl.text.trim())}"');
          b.writeln('        value: "${_esc(o.valueCtrl.text.trim())}"');
        }
      }
      final trs = s.transitions
          .where((t) => t.keywordCtrl.text.trim().isNotEmpty && t.targetState.isNotEmpty)
          .toList();
      if (trs.isNotEmpty) {
        b.writeln('    transitions:');
        for (final t in trs) {
          b.writeln('      - condition: "contains:${t.keywordCtrl.text.trim()}"');
          b.writeln('        target_state: ${t.targetState}');
        }
      }
    }
    return b.toString();
  }

  String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  // ── Save ─────────────────────────────────────────────────────────
  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    if (d.name.isEmpty)   { _showErr('Nome do fluxo é obrigatório'); return; }
    if (d.states.isEmpty) { _showErr('Adicione pelo menos um estado ao fluxo'); return; }

    setState(() => _saving = true);
    try {
      await flowAdminService.saveFlowYaml(flowName: d.name, yamlContent: _toYaml(d));
      await flowAdminService.reloadFlows();
      await _reloadFlows();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fluxo "${d.name}" salvo com sucesso!'),
          backgroundColor: _kSuccess,
        ));
      }
    } catch (e) {
      if (mounted) _showErr('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showNewFlowDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Novo fluxo', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escolha um nome simples, sem espaços.', style: TextStyle(color: _kMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: _kText),
              decoration: InputDecoration(
                labelText: 'Nome do fluxo',
                hintText: 'ex: boas_vindas',
                labelStyle: const TextStyle(color: _kMuted),
                hintStyle: const TextStyle(color: _kSubtle),
                enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _kBorder),
                    borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _kAccent),
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _kMuted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () {
              final name = ctrl.text.trim().replaceAll(' ', '_');
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _draft?.dispose();
                _selectedName = name;
                _draft = _FlowDraft(
                  name: name,
                  description: '',
                  startState: 'inicio',
                  states: [
                    _StateDraft(
                        name: 'inicio',
                        message: 'Olá! Como posso ajudar?',
                        expanded: true),
                  ],
                );
              });
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _kDanger));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLeft(),
          Container(width: 1, color: _kBorder),
          Expanded(child: _buildRight()),
        ],
      ),
    );
  }

  // ── Left panel ────────────────────────────────────────────────────
  Widget _buildLeft() {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder))),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder)),
                    child: const Icon(Icons.arrow_back_rounded, color: _kMuted, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Configurações',
                    style: TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // AI Toggle
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: _aiEnabled ? const Color(0xFF064E3B) : _kCard,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.smart_toy_rounded,
                        color: _aiEnabled ? _kSuccess : _kMuted, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Inteligência Artificial',
                            style: TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(_aiEnabled ? 'Ativada' : 'Desativada',
                            style: TextStyle(
                                color: _aiEnabled ? _kSuccess : _kMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _aiEnabled,
                    activeTrackColor: _kAccent,
                    onChanged: (v) async {
                      setState(() => _aiEnabled = v);
                      try { await tenantService.toggleAi('default', v); } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
          ),
          // Flows header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
            child: Row(
              children: [
                const Text('FLUXOS',
                    style: TextStyle(
                        color: _kSubtle, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                const Spacer(),
                _SmallBtn(icon: Icons.refresh_rounded, tooltip: 'Atualizar', onTap: _reloadFlows),
                const SizedBox(width: 4),
                _SmallBtn(icon: Icons.add_rounded, tooltip: 'Novo fluxo', onTap: _showNewFlowDialog),
              ],
            ),
          ),
          // Flows list
          Expanded(
            child: _loadingFlows
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _flows.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open_rounded, color: _kSubtle, size: 28),
                            SizedBox(height: 8),
                            Text('Nenhum fluxo criado',
                                style: TextStyle(color: _kSubtle, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _flows.length,
                        itemBuilder: (_, i) => _FlowListItem(
                          flow: _flows[i],
                          selected: _flows[i].name == _selectedName,
                          onTap: () => _selectFlow(_flows[i].name),
                        ),
                      ),
          ),
          // Unsaved new flow badge
          if (_selectedName != null && !_flows.any((f) => f.name == _selectedName))
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _FlowListItem(
                flow: FlowSummaryModel(name: _selectedName!, description: 'Novo — não salvo ainda'),
                selected: true,
                onTap: () {},
              ),
            ),
        ],
      ),
    );
  }

  // ── Right panel ──────────────────────────────────────────────────
  Widget _buildRight() {
    if (_selectedName == null) return const _EditorEmpty();
    if (_loadingDraft) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _draft;
    if (d == null) return const _EditorEmpty();
    return _FlowEditorView(
      key: ValueKey(_selectedName),
      draft: d,
      saving: _saving,
      onSave: _save,
      onChanged: () => setState(() {}),
    );
  }
}

// ── Small icon button ─────────────────────────────────────────────
class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBorder)),
          child: Icon(icon, size: 15, color: _kMuted),
        ),
      ),
    );
  }
}

// ── Flow list item ────────────────────────────────────────────────
class _FlowListItem extends StatelessWidget {
  const _FlowListItem({required this.flow, required this.selected, required this.onTap});
  final FlowSummaryModel flow;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kCard : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: _kAccent.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                  color: selected ? _kAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    flow.name,
                    style: TextStyle(
                        color: selected ? _kText : const Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                  if ((flow.description ?? '').isNotEmpty)
                    Text(flow.description!,
                        style: const TextStyle(color: _kSubtle, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (selected) const Icon(Icons.chevron_right_rounded, size: 16, color: _kAccent),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────
class _EditorEmpty extends StatelessWidget {
  const _EditorEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: _kCard, shape: BoxShape.circle, border: Border.all(color: _kBorder)),
            child: const Icon(Icons.account_tree_rounded, size: 38, color: _kAccent),
          ),
          const SizedBox(height: 18),
          const Text('Selecione um fluxo para editar',
              style: TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Ou clique em + para criar um novo fluxo',
              style: TextStyle(color: _kMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Flow editor view ──────────────────────────────────────────────
class _FlowEditorView extends StatefulWidget {
  const _FlowEditorView({
    super.key,
    required this.draft,
    required this.saving,
    required this.onSave,
    required this.onChanged,
  });
  final _FlowDraft draft;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onChanged;

  @override
  State<_FlowEditorView> createState() => _FlowEditorViewState();
}

class _FlowEditorViewState extends State<_FlowEditorView> {
  void _addState() {
    final newName = 'estado_${widget.draft.states.length + 1}';
    setState(() {
      widget.draft.states.add(_StateDraft(name: newName, expanded: true));
      if (widget.draft.startState.isEmpty) widget.draft.startState = newName;
    });
    widget.onChanged();
  }

  void _removeState(int idx) {
    final removed = widget.draft.states[idx];
    final removedName = removed.name;
    setState(() => widget.draft.states.removeAt(idx));
    removed.dispose();
    if (widget.draft.startState == removedName && widget.draft.states.isNotEmpty) {
      widget.draft.startState = widget.draft.states.first.name;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(d),
        Expanded(
          child: d.states.isEmpty
              ? _buildEmptyStates()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: d.states.length + 1,
                  itemBuilder: (_, i) {
                    if (i == d.states.length) return _buildAddBtn();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StateCard(
                        state: d.states[i],
                        stateNames: d.stateNames,
                        onDelete: () => _removeState(i),
                        onChanged: () { setState(() {}); widget.onChanged(); },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTopBar(_FlowDraft d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
          color: _kSurface, border: Border(bottom: BorderSide(color: _kBorder))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Name
          SizedBox(
            width: 220,
            child: _LabeledField(
              label: 'Nome do fluxo',
              child: _DarkField(
                controller: d.nameCtrl,
                hint: 'meu_fluxo',
                onChanged: widget.onChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Description
          Expanded(
            flex: 2,
            child: _LabeledField(
              label: 'Descrição (opcional)',
              child: _DarkField(
                  controller: d.descCtrl, hint: 'Descreva o objetivo deste fluxo', onChanged: widget.onChanged),
            ),
          ),
          const SizedBox(width: 14),
          // Start state
          _LabeledField(
            label: 'Estado inicial',
            child: Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: d.stateNames.contains(d.startState)
                      ? d.startState
                      : (d.stateNames.isEmpty ? null : d.stateNames.first),
                  dropdownColor: _kCard,
                  isDense: true,
                  style: const TextStyle(color: _kText, fontSize: 13),
                  hint: const Text('Selecione', style: TextStyle(color: _kSubtle, fontSize: 13)),
                  items: d.stateNames
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) { setState(() => d.startState = v); widget.onChanged(); }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Save
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: widget.saving ? null : widget.onSave,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(widget.saving ? 'Salvando...' : 'Salvar fluxo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStates() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_box_outlined, size: 44, color: _kSubtle),
          const SizedBox(height: 14),
          const Text('Nenhum estado criado ainda',
              style: TextStyle(color: _kMuted, fontSize: 14)),
          const SizedBox(height: 6),
          const Text(
              'Estados são as etapas da conversa — cada um envia uma mensagem ao usuário.',
              style: TextStyle(color: _kSubtle, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: _addState,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Criar primeiro estado'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBtn() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            foregroundColor: _kMuted,
            side: const BorderSide(color: _kBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _addState,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Adicionar estado'),
      ),
    );
  }
}

// ── State card ────────────────────────────────────────────────────
class _StateCard extends StatefulWidget {
  const _StateCard({
    required this.state,
    required this.stateNames,
    required this.onDelete,
    required this.onChanged,
  });
  final _StateDraft state;
  final List<String> stateNames;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  State<_StateCard> createState() => _StateCardState();
}

class _StateCardState extends State<_StateCard> {
  void _addOption() {
    setState(() => widget.state.options.add(_OptionDraft()));
    widget.onChanged();
  }

  void _removeOption(int i) {
    widget.state.options.removeAt(i).dispose();
    setState(() {});
    widget.onChanged();
  }

  void _addTransition() {
    setState(() => widget.state.transitions.add(_TransitionDraft()));
    widget.onChanged();
  }

  void _removeTransition(int i) {
    widget.state.transitions.removeAt(i).dispose();
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Container(
      decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          GestureDetector(
            onTap: () => setState(() => s.expanded = !s.expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _kCardHdr,
                borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(11),
                    bottom: s.expanded ? Radius.zero : const Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(
                    s.expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.chevron_right_rounded,
                    color: _kMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.circle, color: _kAccent, size: 7),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: s.nameCtrl,
                        onChanged: (_) => widget.onChanged(),
                        style: const TextStyle(
                            color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          hintText: 'nome_do_estado',
                          hintStyle: const TextStyle(color: _kSubtle, fontSize: 13),
                          filled: true,
                          fillColor: _kCard,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _kBorder)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _kBorder)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: _kAccent)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Remover este estado',
                    child: InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded, size: 16, color: _kDanger),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (s.expanded) ...[
            // Message
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(icon: Icons.chat_bubble_outline_rounded, label: 'Mensagem enviada ao usuário'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: s.msgCtrl,
                    onChanged: (_) => widget.onChanged(),
                    maxLines: 3,
                    minLines: 2,
                    style: const TextStyle(color: _kText, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ex: Olá! Como posso ajudar você hoje?',
                      hintStyle: const TextStyle(color: _kSubtle, fontSize: 13),
                      filled: true,
                      fillColor: _kInput,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _kAccent)),
                    ),
                  ),
                ],
              ),
            ),

            // Options
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SectionLabel(
                          icon: Icons.list_alt_rounded, label: 'Opções de resposta (botões)'),
                      const Spacer(),
                      _SmallBtn(
                          icon: Icons.add_rounded,
                          tooltip: 'Adicionar opção',
                          onTap: _addOption),
                    ],
                  ),
                  if (s.options.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Expanded(
                            child: Text('Texto do botão',
                                style: TextStyle(color: _kSubtle, fontSize: 11))),
                        SizedBox(width: 8),
                        Expanded(
                            child: Text('Valor (identificador)',
                                style: TextStyle(color: _kSubtle, fontSize: 11))),
                        SizedBox(width: 30),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...List.generate(s.options.length, (i) {
                      final o = s.options[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                                child: _DarkField(
                                    controller: o.labelCtrl,
                                    hint: 'Ex: Ver produtos',
                                    onChanged: widget.onChanged)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _DarkField(
                                    controller: o.valueCtrl,
                                    hint: 'Ex: ver_produtos',
                                    onChanged: widget.onChanged)),
                            InkWell(
                              onTap: () => _removeOption(i),
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close_rounded, size: 15, color: _kSubtle),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          'Sem opções — clique em + para adicionar botões de resposta.',
                          style: const TextStyle(color: _kSubtle, fontSize: 12)),
                    ),
                ],
              ),
            ),

            // Transitions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SectionLabel(
                          icon: Icons.arrow_forward_rounded, label: 'Regras de transição'),
                      const Spacer(),
                      _SmallBtn(
                          icon: Icons.add_rounded,
                          tooltip: 'Adicionar regra',
                          onTap: _addTransition),
                    ],
                  ),
                  if (s.transitions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...List.generate(s.transitions.length, (i) {
                      final t = s.transitions[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            _PillLabel('Se contiver'),
                            Expanded(
                              child: TextField(
                                controller: t.keywordCtrl,
                                onChanged: (_) => widget.onChanged(),
                                style: const TextStyle(color: _kText, fontSize: 13),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  hintText: 'palavra-chave',
                                  hintStyle: TextStyle(color: _kSubtle, fontSize: 13),
                                  filled: true,
                                  fillColor: _kInput,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: _kBorder)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: _kBorder)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(color: _kAccent)),
                                ),
                              ),
                            ),
                            _PillLabel('→ ir para'),
                            Container(
                              constraints: const BoxConstraints(minWidth: 130),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: const BoxDecoration(
                                color: _kInput,
                                borderRadius:
                                    BorderRadius.horizontal(right: Radius.circular(8)),
                                border: Border(
                                    top: BorderSide(color: _kBorder),
                                    right: BorderSide(color: _kBorder),
                                    bottom: BorderSide(color: _kBorder)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: widget.stateNames.contains(t.targetState)
                                      ? t.targetState
                                      : null,
                                  dropdownColor: _kCard,
                                  isDense: true,
                                  style: const TextStyle(color: _kText, fontSize: 12),
                                  hint: const Text('estado',
                                      style: TextStyle(color: _kSubtle, fontSize: 12)),
                                  items: widget.stateNames
                                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => t.targetState = v);
                                      widget.onChanged();
                                    }
                                  },
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _removeTransition(i),
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close_rounded, size: 15, color: _kSubtle),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          'Sem regras — clique em + para definir quando avançar para outro estado.',
                          style: const TextStyle(color: _kSubtle, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _kMuted),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: _kMuted, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _PillLabel extends StatelessWidget {
  const _PillLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: const BoxDecoration(
          color: _kInput,
          border: Border(
              top: BorderSide(color: _kBorder),
              bottom: BorderSide(color: _kBorder),
              left: BorderSide(color: _kBorder))),
      child: Text(text, style: const TextStyle(color: _kSubtle, fontSize: 12)),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: _kSubtle, fontSize: 11)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField(
      {required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(color: _kText, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          hintText: hint,
          hintStyle: const TextStyle(color: _kSubtle, fontSize: 13),
          filled: true,
          fillColor: _kCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kAccent)),
        ),
      ),
    );
  }
}
