import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import '../services/auth_service.dart';
import '../services/flow_admin_service.dart';
import '../services/tenant_service.dart';

// ââ€â‚¬ââ€â‚¬ Dark palette ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
const _kBg = Color(0xFF0F172A);
const _kSurface = Color(0xFF111827);
const _kCard = Color(0xFF1F2937);
const _kInput = Color(0xFF0F172A);
const _kSubCard = Color(0xFF020617);
const _kBorder = Color(0xFF374151);
const _kText = Color(0xFFE2E8F0);
const _kMuted = Color(0xFF94A3B8);
const _kSubtle = Color(0xFF64748B);
const _kAccent = Color(0xFF7C8CFF);
const _kAccentSoft = Color(0xFF818CF8);
const _kSuccess = Color(0xFF10B981);
const _kDanger = Color(0xFFEF4444);

// ââ€â‚¬ââ€â‚¬ Draft data models ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _OptionDraft {
  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  String targetState;
  _OptionDraft({String label = '', String value = '', this.targetState = ''})
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
  final TextEditingController hookActionCtrl;
  final List<_OptionDraft> options;
  final List<_TransitionDraft> transitions;
  bool requiresHandoff;
  bool expanded;

  _StateDraft({
    String name = '',
    String message = '',
    String hookAction = '',
    List<_OptionDraft>? options,
    List<_TransitionDraft>? transitions,
    this.requiresHandoff = false,
    this.expanded = false,
  })  : nameCtrl = TextEditingController(text: name),
        msgCtrl = TextEditingController(text: message),
        hookActionCtrl = TextEditingController(text: hookAction),
        options = options ?? [],
        transitions = transitions ?? [];

  String get name => nameCtrl.text.trim();
  String get message => msgCtrl.text.trim();

  void dispose() {
    nameCtrl.dispose();
    msgCtrl.dispose();
    hookActionCtrl.dispose();
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

// ââ€â‚¬ââ€â‚¬ Main screen ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _fallbackTenantId = String.fromEnvironment(
    'TENANT_ID',
    defaultValue: 'default',
  );
  String get _tenantId => authService.tenantId ?? _fallbackTenantId;
  bool get _isSystemAdminHomeContext =>
      authService.isSuperadmin &&
      _tenantId == (authService.homeTenantId ?? '');
  List<FlowSummaryModel> _flows = [];
  bool _loadingFlows = true;
  String? _selectedName;
  _FlowDraft? _draft;
  bool _loadingDraft = false;
  bool _saving = false;
  bool _aiEnabled = false;
  bool _savingAiConfig = false;
  String _selectedModel = 'gemini-1.5-flash-latest';
  List<String> _availableModels = const <String>[];
  final TextEditingController _fallbackModelsCtrl = TextEditingController();
  int _rightPanelTab = 0;
  String? _previewCurrentStep;
  List<Map<String, String>> _previewHistory = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _fallbackModelsCtrl.dispose();
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_isSystemAdminHomeContext) {
      if (mounted) {
        setState(() {
          _flows = [];
          _loadingFlows = false;
          _draft?.dispose();
          _draft = null;
          _selectedName = null;
        });
      }
      return;
    }
    try {
      final s = await tenantService.fetchTenantSettings(_tenantId);
      if (mounted) {
        setState(() {
          _aiEnabled = s.aiEnabled;
          _selectedModel = s.geminiModel;
          _availableModels = s.availableModels.isNotEmpty
              ? s.availableModels
              : <String>[s.geminiModel, ...s.fallbackModels];
          _fallbackModelsCtrl.text = s.fallbackModels.join(', ');
        });
      }
    } catch (_) {}
    await _reloadFlows();
  }

  Future<void> _reloadFlows() async {
    if (_isSystemAdminHomeContext) {
      setState(() {
        _flows = [];
        _loadingFlows = false;
      });
      return;
    }
    setState(() => _loadingFlows = true);
    try {
      final flows = await flowAdminService.listFlows();
      if (mounted)
        setState(() {
          _flows = flows;
          _loadingFlows = false;
        });
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
      if (mounted) {
        setState(() {
          _draft = draft;
          _loadingDraft = false;
        });
        _resetPreview(draft);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDraft = false);
        _showErr('Erro ao carregar fluxo: $e');
      }
    }
  }

  // ââ€â‚¬ââ€â‚¬ YAML ââ€ â€ Draft ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
  _FlowDraft _parseYaml(String fallback, String src) {
    try {
      final doc = loadYaml(src);
      if (doc is! Map) return _FlowDraft(name: fallback);
      final data = doc;
      final name = data['name']?.toString() ?? fallback;
      final description = data['description']?.toString() ?? '';
      final rawStartState =
          (data['start_state'] ?? data['start'])?.toString() ?? '';
      final statesMap = data['states'];
      final states = <_StateDraft>[];
      final idToDisplay = <String, String>{};
      if (statesMap is Map) {
        for (final entry in statesMap.entries) {
          final sName = entry.key.toString();
          final sData =
              (entry.value is Map) ? entry.value as Map : <dynamic, dynamic>{};
          final displayName = sData['display_name']?.toString().trim();
          final userFacingName = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : _humanizeStateId(sName);
          final msg = sData['message']?.toString() ?? '';
          final requiresHandoff = sData['requires_handoff'] == true;
          final hookData = sData['hook'];
          final hookAction = (hookData is Map)
              ? (hookData['action'] ?? hookData['name'])?.toString() ?? ''
              : '';
          final opts = <_OptionDraft>[];
          final rawOpts = sData['options'];
          if (rawOpts is List) {
            for (final o in rawOpts) {
              if (o is! Map) continue;
              final lbl = (o['label'] ?? o['text'])?.toString() ?? '';
              final val = (o['value'] ?? o['id'] ?? lbl)?.toString() ?? '';
              opts.add(_OptionDraft(label: lbl, value: val));
            }
          }
          final trans = <_TransitionDraft>[];
          final rawTrans = sData['transitions'];
          if (rawTrans is List) {
            for (final t in rawTrans) {
              if (t is! Map) continue;
              final cond = t['condition']?.toString() ?? '';
              final target = (t['target_state'] ??
                          t['target'] ??
                          t['next_state'] ??
                          t['next'])
                      ?.toString() ??
                  '';
              final kw = cond.startsWith('contains:')
                  ? cond.substring(9).trim()
                  : cond.trim();
              final normalizedKeyword = kw.toLowerCase();
              var consumedByOption = false;
              for (final option in opts) {
                final optionValue = option.valueCtrl.text.trim().toLowerCase();
                final optionLabel = option.labelCtrl.text.trim().toLowerCase();
                if (normalizedKeyword.isNotEmpty &&
                    (normalizedKeyword == optionValue ||
                        normalizedKeyword == optionLabel)) {
                  option.targetState = target;
                  consumedByOption = true;
                  break;
                }
              }
              if (!consumedByOption) {
                trans.add(_TransitionDraft(keyword: kw, targetState: target));
              }
            }
          }
          states.add(_StateDraft(
            name: userFacingName,
            message: msg,
            hookAction: hookAction,
            options: opts,
            transitions: trans,
            requiresHandoff: requiresHandoff,
          ));
          idToDisplay[sName] = userFacingName;
        }

        for (final state in states) {
          for (final option in state.options) {
            final mapped = idToDisplay[option.targetState];
            if (mapped != null) option.targetState = mapped;
          }
          for (final transition in state.transitions) {
            final mapped = idToDisplay[transition.targetState];
            if (mapped != null) transition.targetState = mapped;
          }
        }
      }
      final startDisplay = idToDisplay[rawStartState] ??
          (rawStartState.isNotEmpty ? _humanizeStateId(rawStartState) : '');
      return _FlowDraft(
        name: name,
        description: description,
        startState: startDisplay.isEmpty && states.isNotEmpty
            ? states.first.name
            : startDisplay,
        states: states,
      );
    } catch (_) {
      return _FlowDraft(name: fallback);
    }
  }

  String _slugify(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\- ]'), '')
        .replaceAll(' ', '_');
  }

  String _humanizeStateId(String stateId) {
    final text = stateId.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (text.isEmpty) return 'Passo';
    final words = text.split(RegExp(r'\s+'));
    return words
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Map<String, String> _buildStateIdMap(List<_StateDraft> states) {
    final map = <String, String>{};
    final used = <String>{};
    for (var i = 0; i < states.length; i++) {
      final display = states[i].name.trim().isNotEmpty
          ? states[i].name.trim()
          : 'Passo ${i + 1}';
      final base =
          _slugify(display).isNotEmpty ? _slugify(display) : 'passo_${i + 1}';
      var candidate = base;
      var suffix = 2;
      while (used.contains(candidate)) {
        candidate = '${base}_$suffix';
        suffix++;
      }
      used.add(candidate);
      map[display] = candidate;
    }
    return map;
  }

  String _resolveStateId(String displayName, Map<String, String> stateMap) {
    final exact = stateMap[displayName];
    if (exact != null) return exact;
    final normalized = displayName.trim().toLowerCase();
    for (final entry in stateMap.entries) {
      if (entry.key.trim().toLowerCase() == normalized) return entry.value;
    }
    final fallback = _slugify(displayName);
    return fallback.isNotEmpty ? fallback : 'passo';
  }

  String _autoOptionId(String label, int index) {
    final slug = _slugify(label);
    if (slug.isNotEmpty) return slug;
    return 'botao_${index + 1}';
  }

  _StateDraft? _findStateByDisplayName(_FlowDraft draft, String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) return null;
    for (final state in draft.states) {
      if (state.name.trim().toLowerCase() == displayName.trim().toLowerCase())
        return state;
    }
    return null;
  }

  void _resetPreview(_FlowDraft draft) {
    final start = draft.startState.isNotEmpty
        ? draft.startState
        : (draft.states.isNotEmpty ? draft.states.first.name : '');
    final startState = _findStateByDisplayName(draft, start) ??
        (draft.states.isNotEmpty ? draft.states.first : null);
    setState(() {
      _previewCurrentStep = startState?.name;
      _previewHistory = <Map<String, String>>[];
      if (startState != null && startState.message.isNotEmpty) {
        _previewHistory.add({'role': 'bot', 'text': startState.message});
      }
    });
  }

  void _previewSelectOption(_FlowDraft draft, _OptionDraft option) {
    final current = _findStateByDisplayName(draft, _previewCurrentStep);
    if (current == null) return;

    final chosenLabel = option.labelCtrl.text.trim();
    final nextDisplay = option.targetState.trim();
    final nextState = _findStateByDisplayName(draft, nextDisplay);

    setState(() {
      if (chosenLabel.isNotEmpty) {
        _previewHistory.add({'role': 'user', 'text': chosenLabel});
      }
      if (nextState != null) {
        _previewCurrentStep = nextState.name;
        if (nextState.message.isNotEmpty) {
          _previewHistory.add({'role': 'bot', 'text': nextState.message});
        }
      }
    });
  }

  String _toYaml(_FlowDraft d) {
    final b = StringBuffer();
    final stateIdMap = _buildStateIdMap(d.states);
    final startDisplay = d.startState.isNotEmpty
        ? d.startState
        : (d.states.isNotEmpty ? d.states.first.name : '');
    final start = _resolveStateId(startDisplay, stateIdMap);
    b.writeln('name: ${d.name}');
    if (d.description.isNotEmpty)
      b.writeln('description: "${_esc(d.description)}"');
    b.writeln('start_state: $start');
    b.writeln('states:');
    for (final s in d.states) {
      if (s.name.isEmpty) continue;
      final sourceDisplay = s.name.trim();
      final stateId = _resolveStateId(sourceDisplay, stateIdMap);
      b.writeln('  $stateId:');
      b.writeln('    display_name: "${_esc(sourceDisplay)}"');
      if (s.message.isNotEmpty) b.writeln('    message: "${_esc(s.message)}"');
      if (s.requiresHandoff) b.writeln('    requires_handoff: true');
      if (s.hookActionCtrl.text.trim().isNotEmpty) {
        b.writeln('    hook:');
        b.writeln('      action: "${_esc(s.hookActionCtrl.text.trim())}"');
      }
      final opts =
          s.options.where((o) => o.labelCtrl.text.trim().isNotEmpty).toList();
      if (opts.isNotEmpty) {
        b.writeln('    options:');
        for (var i = 0; i < opts.length; i++) {
          final o = opts[i];
          final optionValue = _autoOptionId(o.labelCtrl.text.trim(), i);
          b.writeln('      - label: "${_esc(o.labelCtrl.text.trim())}"');
          b.writeln('        value: "${_esc(optionValue)}"');
        }
      }
      final trs = <_TransitionDraft>[];
      final seen = <String>{};

      for (var i = 0; i < opts.length; i++) {
        final option = opts[i];
        final target = option.targetState.trim();
        if (target.isEmpty) continue;
        final token = _autoOptionId(option.labelCtrl.text.trim(), i);
        if (token.isEmpty) continue;
        final targetId = _resolveStateId(target, stateIdMap);
        final dedupKey = 'contains:$token->$targetId';
        if (seen.contains(dedupKey)) continue;
        seen.add(dedupKey);
        trs.add(_TransitionDraft(keyword: token, targetState: targetId));
      }

      final freeTextTransitions = s.transitions
          .where((t) =>
              t.keywordCtrl.text.trim().isNotEmpty && t.targetState.isNotEmpty)
          .toList();
      for (final transition in freeTextTransitions) {
        final token = transition.keywordCtrl.text.trim();
        final targetId =
            _resolveStateId(transition.targetState.trim(), stateIdMap);
        final dedupKey = 'contains:$token->$targetId';
        if (seen.contains(dedupKey)) continue;
        seen.add(dedupKey);
        trs.add(_TransitionDraft(keyword: token, targetState: targetId));
      }

      if (trs.isNotEmpty) {
        b.writeln('    transitions:');
        for (final t in trs) {
          b.writeln(
              '      - condition: "contains:${_esc(t.keywordCtrl.text.trim())}"');
          b.writeln('        target_state: ${t.targetState}');
        }
      }
    }
    return b.toString();
  }

  String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  // ââ€â‚¬ââ€â‚¬ Save ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    if (d.name.isEmpty) {
      _showErr('Nome do fluxo e obrigatorio');
      return;
    }
    if (d.states.isEmpty) {
      _showErr('Adicione pelo menos um passo ao fluxo');
      return;
    }
    final seenSteps = <String>{};
    for (final state in d.states) {
      final stepName = state.name.trim();
      if (stepName.isEmpty) {
        _showErr('Preencha o nome de todos os passos.');
        return;
      }
      final normalized = stepName.toLowerCase();
      if (seenSteps.contains(normalized)) {
        _showErr('Existem passos com o mesmo nome. Use nomes diferentes.');
        return;
      }
      seenSteps.add(normalized);
    }
    for (final state in d.states) {
      for (final option in state.options) {
        final hasLabel = option.labelCtrl.text.trim().isNotEmpty;
        if (hasLabel && option.targetState.trim().isEmpty) {
          _showErr(
            'Defina o próximo passo para o botão "${option.labelCtrl.text.trim()}" no passo "${state.name}".',
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      await flowAdminService.saveFlowYaml(
          flowName: d.name, yamlContent: _toYaml(d));
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

  List<String> _parseModelList(String raw) {
    final parts =
        raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final unique = <String>[];
    for (final item in parts) {
      if (!unique.contains(item)) unique.add(item);
    }
    return unique;
  }

  Future<void> _saveAiConfig() async {
    final fallbackModels = _parseModelList(_fallbackModelsCtrl.text);
    if (_selectedModel.trim().isEmpty) {
      _showErr('Selecione um modelo principal');
      return;
    }

    setState(() => _savingAiConfig = true);
    try {
      final updated = await tenantService.updateAiModels(
        tenantId: _tenantId,
        geminiModel: _selectedModel.trim(),
        fallbackModels: fallbackModels,
      );
      if (!mounted) return;
      setState(() {
        _selectedModel = updated.geminiModel;
        _availableModels = updated.availableModels.isNotEmpty
            ? updated.availableModels
            : <String>[updated.geminiModel, ...updated.fallbackModels];
        _fallbackModelsCtrl.text = updated.fallbackModels.join(', ');
        _aiEnabled = updated.aiEnabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuração de IA salva com sucesso'),
          backgroundColor: _kSuccess,
        ),
      );
    } catch (err) {
      if (mounted) _showErr('Erro ao salvar configuração da IA: $err');
    } finally {
      if (mounted) setState(() => _savingAiConfig = false);
    }
  }

  String _normalizeFlowName(String value) {
    final cleaned =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\- ]'), '');
    return cleaned.replaceAll(' ', '_');
  }

  List<_StateDraft> _buildTemplateStates(String template) {
    if (template == 'faq_loja') {
      return [
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Aqui estao algumas duvidas comuns. Escolha uma opcao:',
          expanded: true,
          options: [
            _OptionDraft(
                label: 'Prazo de entrega', targetState: 'Prazo de entrega'),
            _OptionDraft(
                label: 'Formas de pagamento',
                targetState: 'Formas de pagamento'),
            _OptionDraft(
                label: 'Falar com atendente', targetState: 'Atendente humano'),
          ],
        ),
        _StateDraft(
            name: 'Prazo de entrega',
            message: 'Nossos prazos de entrega são de 3 a 7 dias úteis.'),
        _StateDraft(
            name: 'Formas de pagamento',
            message: 'Aceitamos PIX, cartao e dinheiro.'),
        _StateDraft(
          name: 'Atendente humano',
          message: 'Perfeito! Vou encaminhar sua conversa para um atendente.',
          requiresHandoff: true,
        ),
      ];
    }

    if (template == 'restaurante') {
      return [
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Bem-vindo! Como posso ajudar hoje?',
          expanded: true,
          options: [
            _OptionDraft(label: 'Cardapio', targetState: 'Cardapio'),
            _OptionDraft(
                label: 'Horario de funcionamento',
                targetState: 'Horario de funcionamento'),
            _OptionDraft(label: 'Fazer pedido', targetState: 'Fazer pedido'),
            _OptionDraft(
                label: 'Falar com atendente', targetState: 'Atendente humano'),
          ],
        ),
        _StateDraft(
            name: 'Cardapio',
            message: 'Temos pratos executivos, lanches e bebidas.'),
        _StateDraft(
            name: 'Horario de funcionamento',
            message: 'Funcionamos todos os dias, das 11h as 23h.'),
        _StateDraft(
            name: 'Fazer pedido',
          message: 'Me diga o que você deseja pedir para eu te ajudar.'),
        _StateDraft(
          name: 'Atendente humano',
          message: 'Vou encaminhar você para o atendimento humano.',
          requiresHandoff: true,
        ),
      ];
    }

    if (template == 'agendamento') {
      return [
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Oi! Voce quer marcar um horario?',
          expanded: true,
          options: [
            _OptionDraft(
                label: 'Marcar horario', targetState: 'Marcar horario'),
            _OptionDraft(
                label: 'Ver horarios disponiveis',
                targetState: 'Horarios disponiveis'),
            _OptionDraft(
                label: 'Falar com atendente', targetState: 'Atendente humano'),
          ],
        ),
        _StateDraft(
            name: 'Marcar horario',
            message: 'Perfeito. Qual dia e horário você prefere?'),
        _StateDraft(
            name: 'Horarios disponiveis',
            message: 'Temos horarios disponiveis de segunda a sexta.'),
        _StateDraft(
          name: 'Atendente humano',
          message:
              'Vou te encaminhar para um atendente finalizar o agendamento.',
          requiresHandoff: true,
        ),
      ];
    }

    return [
      _StateDraft(
        name: 'Mensagem inicial',
        message: 'Olá! Como posso ajudar você hoje?',
        expanded: true,
        options: [
          _OptionDraft(
              label: 'Falar com atendente', targetState: 'Atendente humano'),
        ],
      ),
      _StateDraft(
        name: 'Atendente humano',
        message: 'Perfeito, vou encaminhar para nossa equipe.',
        requiresHandoff: true,
      ),
    ];
  }

  void _showGuidedFlowDialog() {
    final nameCtrl = TextEditingController();
    String selectedTemplate = 'faq_loja';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _kCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Criar fluxo a partir de modelo',
            style: TextStyle(color: _kText, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha um nome e um modelo pronto. Depois você só edita os textos do seu negócio.',
                style: TextStyle(color: _kMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: _kText),
                decoration: InputDecoration(
                  labelText: 'Nome do fluxo',
                  hintText: 'ex: atendimento_loja',
                  labelStyle: const TextStyle(color: _kMuted),
                  hintStyle: const TextStyle(color: _kSubtle),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _kBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: _kAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _kInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedTemplate,
                    dropdownColor: _kCard,
                    style: const TextStyle(color: _kText, fontSize: 13),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'faq_loja',
                        child: Text('FAQ Loja'),
                      ),
                      DropdownMenuItem(
                        value: 'restaurante',
                        child: Text('Restaurante'),
                      ),
                      DropdownMenuItem(
                        value: 'agendamento',
                        child: Text('Agendamento'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedTemplate = value);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _kMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () {
                final name = _normalizeFlowName(nameCtrl.text);
                if (name.isEmpty) return;
                final states = _buildTemplateStates(selectedTemplate);
                Navigator.pop(ctx);
                setState(() {
                  _draft?.dispose();
                  _selectedName = name;
                  _draft = _FlowDraft(
                    name: name,
                    description: 'Fluxo criado com assistente visual',
                    startState: states.isNotEmpty ? states.first.name : '',
                    states: states,
                  );
                });
                if (_draft != null) _resetPreview(_draft!);
              },
              child: const Text('Criar fluxo'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewFlowDialog() {
    _showGuidedFlowDialog();
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: _kDanger));
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final showPreviewPane = constraints.maxWidth >= 1420;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLeft(),
            Expanded(child: _buildRight()),
            if (showPreviewPane) ...[
              Container(width: 1, color: _kCard),
              SizedBox(
                width: 390,
                child: _buildPreviewPane(),
              ),
            ],
          ],
        );
      },
    );

    if (widget.embedded) {
      return Container(color: _kBg, child: content);
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: content,
    );
  }

  // ââ€â‚¬ââ€â‚¬ Left panel ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
  Widget _buildLeft() {
    return Container(
      width: 356,
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(right: BorderSide(color: _kCard)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _kBorder))),
              child: Row(
                children: [
                  if (!widget.embedded) ...[
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kBorder)),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: _kMuted, size: 16),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  const Text('Configurações',
                      style: TextStyle(
                          color: _kText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: _SidebarPill(
                        icon: Icons.smart_toy_outlined,
                        label: 'IA do chatbot',
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _SidebarPill(
                        icon: Icons.account_tree_outlined,
                        label: 'Modelos de fluxo',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // AI Settings
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildAiConfigCard(),
            ),
            // Flows header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
              child: Row(
                children: [
                  const Text('FLUXOS',
                      style: TextStyle(
                          color: _kSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                  const Spacer(),
                  _SmallBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Atualizar',
                      onTap: _reloadFlows),
                  const SizedBox(width: 4),
                  _SmallBtn(
                      icon: Icons.add_rounded,
                      tooltip: 'Criar por modelo',
                      onTap: _showGuidedFlowDialog),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccentSoft,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _showNewFlowDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Criar fluxo'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kAccentSoft,
                  side: const BorderSide(color: _kAccentSoft),
                ),
                onPressed: _showGuidedFlowDialog,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Criar a partir de modelo'),
              ),
            ),
            // Flows list
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: _loadingFlows
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _flows.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_rounded,
                                    color: _kSubtle, size: 28),
                                SizedBox(height: 8),
                                Text('Nenhum fluxo criado',
                                    style: TextStyle(
                                        color: _kSubtle, fontSize: 12)),
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
            ),
            // Unsaved new flow badge
            if (_selectedName != null &&
                !_flows.any((f) => f.name == _selectedName))
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: _FlowListItem(
                  flow: FlowSummaryModel(
                      name: _selectedName!,
                      description: 'Novo â€” não salvo ainda'),
                  selected: true,
                  onTap: () {},
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiConfigCard() {
    final options = <String>{..._availableModels, _selectedModel}
        .where((e) => e.trim().isNotEmpty)
        .toList();
    options.sort();
    final modelValue = options.contains(_selectedModel) ? _selectedModel : null;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _aiEnabled ? const Color(0xFF064E3B) : _kCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  color: _aiEnabled ? _kSuccess : _kMuted,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inteligência Artificial',
                      style: TextStyle(
                        color: _kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _aiEnabled ? 'Ativada' : 'Desativada',
                      style: TextStyle(
                        color: _aiEnabled ? _kSuccess : _kMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _aiEnabled,
                activeTrackColor: _kAccent,
                onChanged: (v) async {
                  setState(() => _aiEnabled = v);
                  try {
                    final updated = await tenantService.toggleAi(_tenantId, v);
                    if (!mounted) return;
                    setState(() {
                      _aiEnabled = updated.aiEnabled;
                      _selectedModel = updated.geminiModel;
                      _availableModels = updated.availableModels.isNotEmpty
                          ? updated.availableModels
                          : <String>[
                              updated.geminiModel,
                              ...updated.fallbackModels
                            ];
                      _fallbackModelsCtrl.text =
                          updated.fallbackModels.join(', ');
                    });
                  } catch (_) {}
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Modelo principal',
            style: TextStyle(color: _kSubtle, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _kInput,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: modelValue,
                isExpanded: true,
                dropdownColor: _kCard,
                style: const TextStyle(color: _kText, fontSize: 12),
                hint: const Text(
                  'Selecione um modelo',
                  style: TextStyle(color: _kSubtle, fontSize: 12),
                ),
                items: options
                    .map((model) => DropdownMenuItem(
                          value: model,
                          child: Text(model, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedModel = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Modelos de apoio (separados por vírgula)',
            style: TextStyle(color: _kSubtle, fontSize: 11),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _fallbackModelsCtrl,
            style: const TextStyle(color: _kText, fontSize: 12),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'gemini-2.5-flash, gemini-2.0-flash, gemini-1.5-flash',
              hintStyle: const TextStyle(color: _kSubtle, fontSize: 11),
              filled: true,
              fillColor: _kInput,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kAccentSoft,
                foregroundColor: Colors.white,
              ),
              onPressed: _savingAiConfig ? null : _saveAiConfig,
              icon: _savingAiConfig
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(_savingAiConfig ? 'Salvando...' : 'Salvar configuração'),
            ),
          ),
        ],
      ),
    );
  }

  // ââ€â‚¬ââ€â‚¬ Right panel ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
  Widget _buildRight() {
    if (_isSystemAdminHomeContext) {
      return Container(
        color: _kSurface,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'A conta do sistema não possui fluxos próprios. Selecione um cliente na administração SaaS para editar os fluxos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 13, height: 1.5),
            ),
          ),
        ),
      );
    }
    if (_selectedName == null) return const _EditorEmpty();
    if (_loadingDraft) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = _draft;
    if (d == null) return const _EditorEmpty();

    final currentPreviewState = _findStateByDisplayName(d, _previewCurrentStep);
    if (_previewCurrentStep == null || currentPreviewState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetPreview(d);
      });
    }

    final editor = _FlowEditorView(
      key: ValueKey(_selectedName),
      draft: d,
      saving: _saving,
      onSave: _save,
      autoOptionId: _autoOptionId,
      onChanged: () => setState(() {}),
    );

    return Container(color: _kSurface, child: editor);
  }

  Widget _buildPreviewPane() {
    if (_isSystemAdminHomeContext) {
      return Container(
        color: _kSurface,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Selecione um cliente na administração SaaS para usar o simulador e revisar um fluxo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 12, height: 1.45),
            ),
          ),
        ),
      );
    }
    if (_selectedName == null) {
      return Container(
        color: _kSurface,
        child: const Center(
          child: Text(
            'Selecione um fluxo para ver a simulação',
            style: TextStyle(color: _kMuted, fontSize: 12),
          ),
        ),
      );
    }
    if (_loadingDraft) {
      return Container(
        color: _kSurface,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final d = _draft;
    if (d == null) {
      return Container(
        color: _kSurface,
        child: const Center(
          child: Text(
            'Fluxo não carregado',
            style: TextStyle(color: _kMuted, fontSize: 12),
          ),
        ),
      );
    }
    return _buildInsightsPanel(d);
  }

  Widget _buildInsightsPanel(_FlowDraft draft) {
    return Container(
      color: _kSurface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulação da conversa',
                  style: TextStyle(
                      color: _kText, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Veja como o cliente vai conversar no WhatsApp.',
                  style: TextStyle(color: _kMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _rightPanelTab == 0 ? _kAccentSoft : _kCard,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => setState(() => _rightPanelTab = 0),
                        child: const Text('Simulação'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _rightPanelTab == 1 ? _kAccentSoft : _kCard,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => setState(() => _rightPanelTab = 1),
                        child: const Text('Mapa do fluxo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _rightPanelTab == 0
                ? _buildPreviewPanel(draft)
                : _buildFlowVisualizationPanel(draft),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel(_FlowDraft draft) {
    final current = _findStateByDisplayName(draft, _previewCurrentStep) ??
        (draft.states.isNotEmpty ? draft.states.first : null);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Simule a conversa como se fosse o cliente no WhatsApp.',
                  style: TextStyle(color: _kMuted, fontSize: 12),
                ),
              ),
              _SmallBtn(
                icon: Icons.refresh_rounded,
                tooltip: 'Reiniciar simulação',
                onTap: () => _resetPreview(draft),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kSubCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Text(
                    'WhatsApp (simulação)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _previewHistory.length,
                    itemBuilder: (_, i) {
                      final row = _previewHistory[i];
                      final isUser = row['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isUser ? _kAccentSoft : _kCard,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            row['text'] ?? '',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (current != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: current.options
                          .where((o) => o.labelCtrl.text.trim().isNotEmpty)
                          .map(
                            (o) => OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kAccentSoft,
                                side: const BorderSide(color: _kAccentSoft),
                              ),
                              onPressed: o.targetState.trim().isEmpty
                                  ? null
                                  : () => _previewSelectOption(draft, o),
                              child: Text(o.labelCtrl.text.trim()),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlowVisualizationPanel(_FlowDraft draft) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: draft.states.length,
      itemBuilder: (_, index) {
        final state = draft.states[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.name,
                style: const TextStyle(
                    color: _kText, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (state.message.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  state.message,
                  style: const TextStyle(color: _kMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              ...state.options
                  .where((o) => o.labelCtrl.text.trim().isNotEmpty)
                  .map(
                    (o) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Text('- ', style: TextStyle(color: _kSubtle)),
                          Expanded(
                            child: Text(
                              '[${o.labelCtrl.text.trim()}] -> ${o.targetState.isNotEmpty ? o.targetState : 'Sem destino'}',
                              style:
                                  const TextStyle(color: _kText, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

// ââ€â‚¬ââ€â‚¬ Small icon button ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _SidebarPill extends StatelessWidget {
  const _SidebarPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _kMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatefulWidget {
  const _SmallBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_SmallBtn> createState() => _SmallBtnState();
}

class _SmallBtnState extends State<_SmallBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF2B3648) : _kCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBorder),
            ),
            child: Icon(widget.icon, size: 15, color: _kMuted),
          ),
        ),
      ),
    );
  }
}

// ââ€â‚¬ââ€â‚¬ Flow list item ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _FlowListItem extends StatefulWidget {
  const _FlowListItem(
      {required this.flow, required this.selected, required this.onTap});
  final FlowSummaryModel flow;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FlowListItem> createState() => _FlowListItemState();
}

class _FlowListItemState extends State<_FlowListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final flow = widget.flow;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? _kCard
                : (_hovered ? const Color(0xFF19253A) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: _kAccent.withValues(alpha: 0.4))
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ]
                : _hovered
                    ? const [
                        BoxShadow(
                          color: Color(0x10000000),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
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
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400),
                    ),
                    if ((flow.description ?? '').isNotEmpty)
                      Text(flow.description!,
                          style: const TextStyle(color: _kSubtle, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: _kAccent),
            ],
          ),
        ),
      ),
    );
  }
}

// ââ€â‚¬ââ€â‚¬ Empty state ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
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
                color: _kCard,
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder)),
            child: const Icon(Icons.account_tree_rounded,
                size: 38, color: _kAccent),
          ),
          const SizedBox(height: 18),
          const Text('Selecione um fluxo para editar',
              style: TextStyle(
                  color: _kText, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Ou clique em + para criar um novo fluxo',
              style: TextStyle(color: _kMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ââ€â‚¬ââ€â‚¬ Flow editor view ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _FlowEditorView extends StatefulWidget {
  const _FlowEditorView({
    super.key,
    required this.draft,
    required this.saving,
    required this.onSave,
    required this.autoOptionId,
    required this.onChanged,
  });
  final _FlowDraft draft;
  final bool saving;
  final VoidCallback onSave;
  final String Function(String label, int index) autoOptionId;
  final VoidCallback onChanged;

  @override
  State<_FlowEditorView> createState() => _FlowEditorViewState();
}

class _FlowEditorViewState extends State<_FlowEditorView> {
  void _addState() {
    final newName = 'Passo ${widget.draft.states.length + 1}';
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
    if (widget.draft.startState == removedName &&
        widget.draft.states.isNotEmpty) {
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _buildQuickGuide(),
        ),
        Expanded(
          child: d.states.isEmpty
              ? _buildEmptyStates()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  itemCount: d.states.length + 1,
                  itemBuilder: (_, i) {
                    if (i == d.states.length) return _buildAddBtn();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _StateCard(
                        state: d.states[i],
                        stepNumber: i + 1,
                        stateNames: d.stateNames,
                        autoOptionId: widget.autoOptionId,
                        onDelete: () => _removeState(i),
                        onChanged: () {
                          setState(() {});
                          widget.onChanged();
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQuickGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: _kAccentSoft, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guia rápido',
                  style: TextStyle(
                      color: _kText, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  '1. Escreva a mensagem do passo\n'
                  '2. Adicione botões de resposta\n'
                  '3. Escolha o próximo passo de cada botão',
                  style: TextStyle(color: _kMuted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(_FlowDraft d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 220,
            child: _LabeledField(
              label: 'Nome do fluxo',
              child: _DarkField(
                controller: d.nameCtrl,
                hint: 'Ex: Atendimento da loja',
                onChanged: widget.onChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: _LabeledField(
              label: 'Descrição (opcional)',
              child: _DarkField(
                controller: d.descCtrl,
                hint: 'Descreva o objetivo deste fluxo',
                onChanged: widget.onChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          _LabeledField(
            label: 'Primeiro passo',
            child: Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: d.stateNames.contains(d.startState)
                      ? d.startState
                      : (d.stateNames.isEmpty ? null : d.stateNames.first),
                  dropdownColor: _kCard,
                  isDense: true,
                  style: const TextStyle(color: _kText, fontSize: 13),
                  hint: const Text('Selecione',
                      style: TextStyle(color: _kSubtle, fontSize: 13)),
                  items: d.stateNames
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => d.startState = v);
                      widget.onChanged();
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kAccentSoft,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: widget.saving ? null : widget.onSave,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
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
          const Text('Nenhum passo criado ainda',
              style: TextStyle(color: _kMuted, fontSize: 14)),
          const SizedBox(height: 6),
          const Text(
            'Passos são as etapas da conversa e cada passo envia uma mensagem ao cliente.',
            style: TextStyle(color: _kSubtle, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: _addState,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Criar primeiro passo'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBtn() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kAccentSoft,
          side: const BorderSide(color: _kAccentSoft),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: _addState,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('Adicionar passo'),
      ),
    );
  }
}

// ââ€â‚¬ââ€â‚¬ State card ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _StateCard extends StatefulWidget {
  const _StateCard({
    required this.state,
    required this.stepNumber,
    required this.stateNames,
    required this.autoOptionId,
    required this.onDelete,
    required this.onChanged,
  });
  final _StateDraft state;
  final int stepNumber;
  final List<String> stateNames;
  final String Function(String label, int index) autoOptionId;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  State<_StateCard> createState() => _StateCardState();
}

class _StateCardState extends State<_StateCard> {
  bool _hovered = false;

  void _addOption() {
    final nextValue = 'opcao_${widget.state.options.length + 1}';
    setState(() => widget.state.options.add(_OptionDraft(value: nextValue)));
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

  Widget _sectionDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      height: 1,
      color: _kBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final title = s.nameCtrl.text.trim().isEmpty
        ? 'Nome do passo'
        : s.nameCtrl.text.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: const Color(0x40000000),
              blurRadius: _hovered ? 14 : 10,
              offset: Offset(0, _hovered ? 6 : 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => s.expanded = !s.expanded),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(11),
                bottom: s.expanded ? Radius.zero : const Radius.circular(11),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(11),
                    bottom:
                        s.expanded ? Radius.zero : const Radius.circular(11),
                  ),
                  border: const Border(bottom: BorderSide(color: _kBorder)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Text(
                        'Passo ${widget.stepNumber}',
                        style: const TextStyle(
                          color: _kMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.circle, color: _kAccent, size: 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      s.expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      color: _kMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Remover este passo',
                      child: InkWell(
                        onTap: widget.onDelete,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 16, color: _kDanger),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (s.expanded)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                        icon: Icons.label_outline_rounded,
                        label: 'Nome do passo'),
                    const SizedBox(height: 8),
                    _DarkField(
                      controller: s.nameCtrl,
                      hint: 'Ex: Mensagem inicial',
                      onChanged: () {
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Mensagem enviada ao usuário',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: s.msgCtrl,
                      onChanged: (_) => widget.onChanged(),
                      maxLines: 4,
                      minLines: 3,
                      style: const TextStyle(color: _kText, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ex: Olá! Como posso ajudar você hoje?',
                        hintStyle:
                            const TextStyle(color: _kSubtle, fontSize: 13),
                        filled: true,
                        fillColor: _kSubCard,
                        contentPadding: const EdgeInsets.all(12),
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
                      ),
                    ),
                    _sectionDivider(),
                    _SectionLabel(
                        icon: Icons.settings_suggest_outlined,
                        label: 'Ações adicionais'),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Encaminhar conversa para atendente humano',
                                  style: TextStyle(
                                    color: _kMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Switch(
                                value: s.requiresHandoff,
                                activeTrackColor: _kAccent,
                                onChanged: (v) {
                                  setState(() => s.requiresHandoff = v);
                                  widget.onChanged();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Integração com sistema (opcional)',
                            style: TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Execute uma ação no seu sistema, como consultar pedido ou saldo.',
                            style: TextStyle(color: _kSubtle, fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          _DarkField(
                            controller: s.hookActionCtrl,
                            hint: 'Ex: consultar_pedido',
                            onChanged: widget.onChanged,
                          ),
                        ],
                      ),
                    ),
                    _sectionDivider(),
                    _buildOptionsSection(s),
                    _sectionDivider(),
                    _buildTransitionsSection(s),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsSection(_StateDraft s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionLabel(
                icon: Icons.list_alt_rounded,
                label: 'Opções de resposta (botões)'),
            const Spacer(),
            _DashedActionButton(
              icon: Icons.add_rounded,
              label: 'Adicionar botão de resposta',
              onTap: _addOption,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Identificador (gerado automaticamente): você define só texto e próximo passo.',
          style: TextStyle(color: _kSubtle, fontSize: 11),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: s.options.isEmpty
              ? const Padding(
                  key: ValueKey('options-empty'),
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'Sem opções ainda. Clique em "Adicionar botão de resposta".',
                    style: TextStyle(color: _kSubtle, fontSize: 12),
                  ),
                )
              : Column(
                  key: ValueKey('options-${s.options.length}'),
                  children: List.generate(s.options.length, (i) {
                    final o = s.options[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kSubCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Texto do botão',
                                    style: TextStyle(
                                        color: _kSubtle, fontSize: 11)),
                                const SizedBox(height: 4),
                                _DarkField(
                                  controller: o.labelCtrl,
                                  hint: 'Ex: Prazo de entrega',
                                  onChanged: () {
                                    setState(() {});
                                    widget.onChanged();
                                  },
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Identificador: ${widget.autoOptionId(o.labelCtrl.text.trim(), i)}',
                                  style: const TextStyle(
                                      color: _kSubtle, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Próximo passo',
                                    style: TextStyle(
                                        color: _kSubtle, fontSize: 11)),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: _kInput,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _kBorder),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: widget.stateNames
                                              .contains(o.targetState)
                                          ? o.targetState
                                          : null,
                                      hint: const Text(
                                        'Selecionar',
                                        style: TextStyle(
                                            color: _kSubtle, fontSize: 12),
                                      ),
                                      isExpanded: true,
                                      dropdownColor: _kCard,
                                      style: const TextStyle(
                                          color: _kText, fontSize: 12),
                                      items: widget.stateNames
                                          .map((n) => DropdownMenuItem(
                                              value: n, child: Text(n)))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => o.targetState = v);
                                        widget.onChanged();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _removeOption(i),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close_rounded,
                                  size: 15, color: _kSubtle),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
        ),
      ],
    );
  }

  Widget _buildTransitionsSection(_StateDraft s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionLabel(
              icon: Icons.arrow_forward_rounded,
              label: 'Respostas digitadas pelo cliente',
            ),
            const Spacer(),
            _SmallBtn(
              icon: Icons.add_rounded,
              tooltip: 'Adicionar resposta digitada',
              onTap: _addTransition,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Se o cliente digitar estas palavras, o chatbot irá responder com este passo.',
          style: TextStyle(color: _kSubtle, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kSubCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: s.transitions.isEmpty
              ? const Text(
                  'Sem respostas digitadas configuradas. Pode deixar vazio se usar botões.',
                  style: TextStyle(color: _kSubtle, fontSize: 12),
                )
              : Column(
                  children: List.generate(s.transitions.length, (i) {
                    final t = s.transitions[i];
                    return Container(
                      margin: EdgeInsets.only(
                          bottom: i == s.transitions.length - 1 ? 0 : 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _kInput,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Quando escrever',
                                    style: TextStyle(
                                        color: _kSubtle, fontSize: 11)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: t.keywordCtrl,
                                  onChanged: (_) => widget.onChanged(),
                                  style: const TextStyle(
                                      color: _kText, fontSize: 13),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 9),
                                    hintText: 'Ex: entrega',
                                    hintStyle: const TextStyle(
                                        color: _kSubtle, fontSize: 13),
                                    filled: true,
                                    fillColor: _kSubCard,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          const BorderSide(color: _kBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          const BorderSide(color: _kBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          const BorderSide(color: _kAccent),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ir para',
                                    style: TextStyle(
                                        color: _kSubtle, fontSize: 11)),
                                const SizedBox(height: 4),
                                Container(
                                  height: 36,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: _kSubCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _kBorder),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: widget.stateNames
                                              .contains(t.targetState)
                                          ? t.targetState
                                          : null,
                                      dropdownColor: _kCard,
                                      isDense: true,
                                      style: const TextStyle(
                                          color: _kText, fontSize: 12),
                                      hint: const Text('Selecionar',
                                          style: TextStyle(
                                              color: _kSubtle, fontSize: 12)),
                                      items: widget.stateNames
                                          .map((n) => DropdownMenuItem(
                                              value: n, child: Text(n)))
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
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _removeTransition(i),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close_rounded,
                                  size: 15, color: _kSubtle),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
        ),
      ],
    );
  }
}

// ââ€â‚¬ââ€â‚¬ Helper widgets ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬ââ€â‚¬
class _DashedActionButton extends StatelessWidget {
  const _DashedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: const _DashedRoundedPainter(color: _kAccentSoft),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: _kAccentSoft),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _kAccentSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRoundedPainter extends CustomPainter {
  const _DashedRoundedPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)));

    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          hintText: hint,
          hintStyle: const TextStyle(color: _kSubtle, fontSize: 13),
          filled: true,
          fillColor: _kSubCard,
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


