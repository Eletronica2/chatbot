import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:yaml/yaml.dart';

import '../services/auth_service.dart';
import '../services/flow_admin_service.dart';
import '../services/tenant_service.dart';

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
  Offset position;

  _StateDraft({
    String name = '',
    String message = '',
    String hookAction = '',
    List<_OptionDraft>? options,
    List<_TransitionDraft>? transitions,
    this.requiresHandoff = false,
    this.expanded = false,
    this.position = Offset.zero,
  })  : nameCtrl = TextEditingController(text: name),
        msgCtrl = TextEditingController(text: message),
        hookActionCtrl = TextEditingController(text: hookAction),
        options = options ?? <_OptionDraft>[],
        transitions = transitions ?? <_TransitionDraft>[];

  String get name => nameCtrl.text.trim();

  String get message => msgCtrl.text.trim();

  void dispose() {
    nameCtrl.dispose();
    msgCtrl.dispose();
    hookActionCtrl.dispose();
    for (final option in options) {
      option.dispose();
    }
    for (final transition in transitions) {
      transition.dispose();
    }
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
        states = states ?? <_StateDraft>[];

  String get name => nameCtrl.text.trim();

  String get description => descCtrl.text.trim();

  List<String> get stateNames =>
      states.map((state) => state.name).where((name) => name.isNotEmpty).toList();

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    for (final state in states) {
      state.dispose();
    }
  }
}

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
      authService.isSuperadmin && _tenantId == (authService.homeTenantId ?? '');

  final TextEditingController _simulationInputCtrl = TextEditingController();
  final ScrollController _simulationScrollCtrl = ScrollController();

  List<FlowSummaryModel> _flows = <FlowSummaryModel>[];
  bool _loadingFlows = true;
  _FlowDraft? _draft;
  bool _saving = false;
  bool _aiEnabled = false;
  bool _sendingSimulation = false;
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
    _simulationInputCtrl.dispose();
    _simulationScrollCtrl.dispose();
    _draft?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_isSystemAdminHomeContext) {
      if (!mounted) {
        return;
      }
      setState(() {
        _flows = <FlowSummaryModel>[];
        _loadingFlows = false;
        _draft?.dispose();
        _draft = null;
      });
      return;
    }

    try {
      final settings = await tenantService.fetchTenantSettings(_tenantId);
      if (mounted) {
        setState(() => _aiEnabled = settings.aiEnabled);
      }
    } catch (_) {}

    await _reloadFlows();
  }

  Future<void> _reloadFlows() async {
    if (_isSystemAdminHomeContext) {
      if (!mounted) {
        return;
      }
      setState(() {
        _flows = <FlowSummaryModel>[];
        _loadingFlows = false;
      });
      return;
    }

    setState(() => _loadingFlows = true);
    try {
      final flows = await flowAdminService.listFlows();
      if (mounted) {
        setState(() {
          _flows = flows;
          _loadingFlows = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingFlows = false);
      }
    }
  }

  Future<void> _selectFlow(String name) async {
    setState(() {
      _draft?.dispose();
      _draft = null;
    });

    try {
      final yaml = await flowAdminService.getFlowYaml(name);
      final draft = _parseYaml(name, yaml);
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = draft;
      });
      _resetPreview(draft);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErr('Erro ao carregar automa\u00e7\u00e3o: $error');
    }
  }

  _FlowDraft _parseYaml(String fallback, String src) {
    try {
      final doc = loadYaml(src);
      if (doc is! Map) {
        return _FlowDraft(name: fallback);
      }

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
          final stateId = entry.key.toString();
          final stateData = entry.value is Map
              ? entry.value as Map
              : <dynamic, dynamic>{};
          final displayName = stateData['display_name']?.toString().trim();
          final userFacingName =
              displayName != null && displayName.isNotEmpty
                  ? displayName
                  : _humanizeStateId(stateId);
          final message = stateData['message']?.toString() ?? '';
          final requiresHandoff = stateData['requires_handoff'] == true;
          final hookData = stateData['hook'];
          final hookAction = hookData is Map
              ? (hookData['action'] ?? hookData['name'])?.toString() ?? ''
              : '';

          final options = <_OptionDraft>[];
          final rawOptions = stateData['options'];
          if (rawOptions is List) {
            for (final rawOption in rawOptions) {
              if (rawOption is! Map) {
                continue;
              }
              final label = (rawOption['label'] ?? rawOption['text'])?.toString() ?? '';
              final value = (rawOption['value'] ?? rawOption['id'] ?? label)
                      ?.toString() ??
                  '';
              options.add(_OptionDraft(label: label, value: value));
            }
          }

          final transitions = <_TransitionDraft>[];
          final rawTransitions = stateData['transitions'];
          if (rawTransitions is List) {
            for (final rawTransition in rawTransitions) {
              if (rawTransition is! Map) {
                continue;
              }
              final condition = rawTransition['condition']?.toString() ?? '';
              final target = (rawTransition['target_state'] ??
                          rawTransition['target'] ??
                          rawTransition['next_state'] ??
                          rawTransition['next'])
                      ?.toString() ??
                  '';
              final keyword = condition.startsWith('contains:')
                  ? condition.substring(9).trim()
                  : condition.trim();
              final normalizedKeyword = keyword.toLowerCase();
              var consumedByOption = false;

              for (final option in options) {
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
                transitions.add(
                  _TransitionDraft(keyword: keyword, targetState: target),
                );
              }
            }
          }

          states.add(
            _StateDraft(
              name: userFacingName,
              message: message,
              hookAction: hookAction,
              options: options,
              transitions: transitions,
              requiresHandoff: requiresHandoff,
            ),
          );
          idToDisplay[stateId] = userFacingName;
        }

        for (final state in states) {
          for (final option in state.options) {
            final mappedTarget = idToDisplay[option.targetState];
            if (mappedTarget != null) {
              option.targetState = mappedTarget;
            }
          }
          for (final transition in state.transitions) {
            final mappedTarget = idToDisplay[transition.targetState];
            if (mappedTarget != null) {
              transition.targetState = mappedTarget;
            }
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
    if (text.isEmpty) {
      return 'Etapa';
    }
    final words = text.split(RegExp(r'\s+'));
    return words
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Map<String, String> _buildStateIdMap(List<_StateDraft> states) {
    final map = <String, String>{};
    final used = <String>{};

    for (var index = 0; index < states.length; index++) {
      final display = states[index].name.trim().isNotEmpty
          ? states[index].name.trim()
          : 'Etapa ${index + 1}';
      final base = _slugify(display).isNotEmpty
          ? _slugify(display)
          : 'etapa_${index + 1}';
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
    if (exact != null) {
      return exact;
    }

    final normalizedDisplay = displayName.trim().toLowerCase();
    for (final entry in stateMap.entries) {
      if (entry.key.trim().toLowerCase() == normalizedDisplay) {
        return entry.value;
      }
    }

    final fallback = _slugify(displayName);
    return fallback.isNotEmpty ? fallback : 'etapa';
  }

  String _autoOptionId(String label, int index) {
    final slug = _slugify(label);
    if (slug.isNotEmpty) {
      return slug;
    }
    return 'botao_${index + 1}';
  }

  _StateDraft? _findStateByDisplayName(_FlowDraft draft, String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) {
      return null;
    }

    for (final state in draft.states) {
      if (state.name.trim().toLowerCase() == displayName.trim().toLowerCase()) {
        return state;
      }
    }

    return null;
  }

  void _handleDraftChanged() {
    final draft = _draft;
    if (draft == null) {
      setState(() {});
      return;
    }

    setState(() {});
  }

  void _scrollSimulationToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_simulationScrollCtrl.hasClients) {
        return;
      }
      final position = _simulationScrollCtrl.position.maxScrollExtent;
      _simulationScrollCtrl.animateTo(
        position,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _resetPreview(_FlowDraft draft) {
    final startDisplay = draft.startState.isNotEmpty
        ? draft.startState
        : (draft.states.isNotEmpty ? draft.states.first.name : '');
    final startState = _findStateByDisplayName(draft, startDisplay) ??
        (draft.states.isNotEmpty ? draft.states.first : null);

    setState(() {
      _previewCurrentStep = startState?.name;
      _previewHistory = <Map<String, String>>[];
      _simulationInputCtrl.clear();
      if (startState != null && startState.message.isNotEmpty) {
        _previewHistory.add(<String, String>{
          'role': 'bot',
          'text': startState.message,
        });
      }
    });

    _scrollSimulationToBottom();
  }

  bool _matchesMessage(String message, String candidate) {
    final normalizedMessage = message.trim().toLowerCase();
    final normalizedCandidate = candidate.trim().toLowerCase();
    if (normalizedMessage.isEmpty || normalizedCandidate.isEmpty) {
      return false;
    }
    return normalizedMessage == normalizedCandidate ||
        normalizedMessage.contains(normalizedCandidate);
  }

  _StateDraft? _resolveNextStateForMessage(
    _FlowDraft draft,
    _StateDraft current,
    String message,
  ) {
    for (var index = 0; index < current.options.length; index++) {
      final option = current.options[index];
      final targetDisplay = option.targetState.trim();
      if (targetDisplay.isEmpty) {
        continue;
      }

      final optionLabel = option.labelCtrl.text.trim();
      final optionToken = _autoOptionId(optionLabel, index);
      if (_matchesMessage(message, optionLabel) ||
          _matchesMessage(message, optionToken)) {
        return _findStateByDisplayName(draft, targetDisplay);
      }
    }

    for (final transition in current.transitions) {
      final targetDisplay = transition.targetState.trim();
      if (targetDisplay.isEmpty) {
        continue;
      }

      final keyword = transition.keywordCtrl.text.trim();
      if (_matchesMessage(message, keyword)) {
        return _findStateByDisplayName(draft, targetDisplay);
      }
    }

    return null;
  }

  String _buildSimulationFallback(_StateDraft current, String message) {
    if (current.requiresHandoff) {
      return 'Esta etapa encaminha a conversa para um atendente humano.';
    }

    final hasConfiguredOptions = current.options.any(
      (option) =>
          option.labelCtrl.text.trim().isNotEmpty &&
          option.targetState.trim().isNotEmpty,
    );
    final hasConfiguredTransitions = current.transitions.any(
      (transition) =>
          transition.keywordCtrl.text.trim().isNotEmpty &&
          transition.targetState.trim().isNotEmpty,
    );

    if (hasConfiguredOptions || hasConfiguredTransitions) {
      return 'Nenhuma proxima etapa foi encontrada para "$message". Revise os botoes ou as respostas digitadas desta etapa.';
    }

    return 'Esta etapa nao possui proximos passos configurados para continuar o teste.';
  }

  Future<void> _runSimulationMessage(_FlowDraft draft, String rawMessage) async {
    if (_sendingSimulation) {
      return;
    }

    final message = rawMessage.trim();
    if (message.isEmpty) {
      return;
    }

    final current = _findStateByDisplayName(draft, _previewCurrentStep) ??
        (draft.states.isNotEmpty ? draft.states.first : null);
    if (current == null) {
      return;
    }

    setState(() {
      _sendingSimulation = true;
      _simulationInputCtrl.clear();
      _previewHistory.add(<String, String>{
        'role': 'user',
        'text': message,
      });
    });

    try {
      final nextState = _resolveNextStateForMessage(draft, current, message);
      if (!mounted) {
        return;
      }

      setState(() {
        if (nextState != null) {
          _previewCurrentStep = nextState.name;
          if (nextState.message.isNotEmpty) {
            _previewHistory.add(<String, String>{
              'role': 'bot',
              'text': nextState.message,
            });
          }
        } else {
          _previewHistory.add(<String, String>{
            'role': 'bot',
            'text': _buildSimulationFallback(current, message),
          });
        }
      });
    } finally {
      if (mounted) {
        setState(() => _sendingSimulation = false);
      }
      _scrollSimulationToBottom();
    }
  }

  void _previewSelectOption(_FlowDraft draft, _OptionDraft option) {
    _runSimulationMessage(draft, option.labelCtrl.text.trim());
  }

  String _toYaml(_FlowDraft draft) {
    final buffer = StringBuffer();
    final stateIdMap = _buildStateIdMap(draft.states);
    final startDisplay = draft.startState.isNotEmpty
        ? draft.startState
        : (draft.states.isNotEmpty ? draft.states.first.name : '');
    final start = _resolveStateId(startDisplay, stateIdMap);

    buffer.writeln('name: ${draft.name}');
    if (draft.description.isNotEmpty) {
      buffer.writeln('description: "${_esc(draft.description)}"');
    }
    buffer.writeln('start_state: $start');
    buffer.writeln('states:');

    for (final state in draft.states) {
      if (state.name.isEmpty) {
        continue;
      }

      final sourceDisplay = state.name.trim();
      final stateId = _resolveStateId(sourceDisplay, stateIdMap);
      buffer.writeln('  $stateId:');
      buffer.writeln('    display_name: "${_esc(sourceDisplay)}"');
      if (state.message.isNotEmpty) {
        buffer.writeln('    message: "${_esc(state.message)}"');
      }
      if (state.requiresHandoff) {
        buffer.writeln('    requires_handoff: true');
      }
      if (state.hookActionCtrl.text.trim().isNotEmpty) {
        buffer.writeln('    hook:');
        buffer.writeln(
          '      action: "${_esc(state.hookActionCtrl.text.trim())}"',
        );
      }

      final options =
          state.options.where((option) => option.labelCtrl.text.trim().isNotEmpty).toList();
      if (options.isNotEmpty) {
        buffer.writeln('    options:');
        for (var index = 0; index < options.length; index++) {
          final option = options[index];
          final optionValue = _autoOptionId(option.labelCtrl.text.trim(), index);
          buffer.writeln('      - label: "${_esc(option.labelCtrl.text.trim())}"');
          buffer.writeln('        value: "${_esc(optionValue)}"');
        }
      }

      final transitions = <_TransitionDraft>[];
      final seen = <String>{};

      for (var index = 0; index < options.length; index++) {
        final option = options[index];
        final targetDisplay = option.targetState.trim();
        if (targetDisplay.isEmpty) {
          continue;
        }
        final token = _autoOptionId(option.labelCtrl.text.trim(), index);
        if (token.isEmpty) {
          continue;
        }
        final targetId = _resolveStateId(targetDisplay, stateIdMap);
        final dedupKey = 'contains:$token->$targetId';
        if (seen.contains(dedupKey)) {
          continue;
        }
        seen.add(dedupKey);
        transitions.add(_TransitionDraft(keyword: token, targetState: targetId));
      }

      final freeTextTransitions = state.transitions
          .where((transition) =>
              transition.keywordCtrl.text.trim().isNotEmpty &&
              transition.targetState.isNotEmpty)
          .toList();

      for (final transition in freeTextTransitions) {
        final token = transition.keywordCtrl.text.trim();
        final targetId =
            _resolveStateId(transition.targetState.trim(), stateIdMap);
        final dedupKey = 'contains:$token->$targetId';
        if (seen.contains(dedupKey)) {
          continue;
        }
        seen.add(dedupKey);
        transitions.add(_TransitionDraft(keyword: token, targetState: targetId));
      }

      if (transitions.isNotEmpty) {
        buffer.writeln('    transitions:');
        for (final transition in transitions) {
          buffer.writeln(
            '      - condition: "contains:${_esc(transition.keywordCtrl.text.trim())}"',
          );
          buffer.writeln('        target_state: ${transition.targetState}');
        }
      }
    }

    return buffer.toString();
  }

  String _esc(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }

    if (draft.name.isEmpty) {
      _showErr('O nome da automa\u00e7\u00e3o \u00e9 obrigat\u00f3rio.');
      return;
    }

    if (draft.states.isEmpty) {
      _showErr('Adicione pelo menos uma etapa na automa\u00e7\u00e3o.');
      return;
    }

    final seenSteps = <String>{};
    for (final state in draft.states) {
      final stepName = state.name.trim();
      if (stepName.isEmpty) {
        _showErr('Preencha o nome de todas as etapas.');
        return;
      }
      final normalized = stepName.toLowerCase();
      if (seenSteps.contains(normalized)) {
        _showErr('Existem etapas com o mesmo nome. Use nomes diferentes.');
        return;
      }
      seenSteps.add(normalized);
    }

    for (final state in draft.states) {
      for (final option in state.options) {
        final hasLabel = option.labelCtrl.text.trim().isNotEmpty;
        if (hasLabel && option.targetState.trim().isEmpty) {
          _showErr(
            'Defina a proxima etapa para o botao "${option.labelCtrl.text.trim()}" na etapa "${state.name}".',
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      await flowAdminService.saveFlowYaml(
        flowName: draft.name,
        yamlContent: _toYaml(draft),
      );
      await flowAdminService.reloadFlows();
      await _reloadFlows();
      if (!mounted) {
        return;
      }
      _resetPreview(draft);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Automa\u00e7\u00e3o "${draft.name}" salva com sucesso!'),
          backgroundColor: _kSuccess,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showErr('Erro ao salvar: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _toggleAi(bool enabled) async {
    final previousValue = _aiEnabled;
    setState(() => _aiEnabled = enabled);
    try {
      final updated = await tenantService.toggleAi(_tenantId, enabled);
      if (!mounted) {
        return;
      }
      setState(() => _aiEnabled = updated.aiEnabled);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _aiEnabled = previousValue);
      _showErr('Erro ao atualizar IA: $error');
    }
  }

  String _normalizeFlowName(String value) {
    final cleaned =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_\- ]'), '');
    return cleaned.replaceAll(' ', '_');
  }

  List<_StateDraft> _buildBlankStates() {
    return <_StateDraft>[
      _StateDraft(
        name: 'Mensagem inicial',
        expanded: true,
      ),
    ];
  }

  String _templateLabel(String template) {
    switch (template) {
      case 'faq_loja':
        return 'FAQ Loja';
      case 'restaurante':
        return 'Restaurante';
      case 'agendamento':
        return 'Agendamento';
      default:
        return 'Modelo personalizado';
    }
  }

  String _templateDescription(String template) {
    switch (template) {
      case 'faq_loja':
        return 'Cria uma base com perguntas frequentes, opcoes de atendimento e encaminhamento para humano.';
      case 'restaurante':
        return 'Sugere um fluxo inicial com cardapio, horario de funcionamento e pedido.';
      case 'agendamento':
        return 'Monta um rascunho com marcacao de horario, disponibilidade e encaminhamento.';
      default:
        return 'Preenche um fluxo inicial para voce editar depois.';
    }
  }

  List<_StateDraft> _buildTemplateStates(String template) {
    if (template == 'faq_loja') {
      return <_StateDraft>[
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Aqui estao algumas duvidas comuns. Escolha uma opcao:',
          expanded: true,
          options: <_OptionDraft>[
            _OptionDraft(
              label: 'Prazo de entrega',
              targetState: 'Prazo de entrega',
            ),
            _OptionDraft(
              label: 'Formas de pagamento',
              targetState: 'Formas de pagamento',
            ),
            _OptionDraft(
              label: 'Falar com atendente',
              targetState: 'Atendente humano',
            ),
          ],
        ),
        _StateDraft(
          name: 'Prazo de entrega',
          message: 'Nossos prazos de entrega sao de 3 a 7 dias uteis.',
        ),
        _StateDraft(
          name: 'Formas de pagamento',
          message: 'Aceitamos PIX, cartao e dinheiro.',
        ),
        _StateDraft(
          name: 'Atendente humano',
          message: 'Perfeito! Vou encaminhar sua conversa para um atendente.',
          requiresHandoff: true,
        ),
      ];
    }

    if (template == 'restaurante') {
      return <_StateDraft>[
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Bem-vindo! Como posso ajudar hoje?',
          expanded: true,
          options: <_OptionDraft>[
            _OptionDraft(label: 'Cardapio', targetState: 'Cardapio'),
            _OptionDraft(
              label: 'Horario de funcionamento',
              targetState: 'Horario de funcionamento',
            ),
            _OptionDraft(label: 'Fazer pedido', targetState: 'Fazer pedido'),
            _OptionDraft(
              label: 'Falar com atendente',
              targetState: 'Atendente humano',
            ),
          ],
        ),
        _StateDraft(
          name: 'Cardapio',
          message: 'Temos pratos executivos, lanches e bebidas.',
        ),
        _StateDraft(
          name: 'Horario de funcionamento',
          message: 'Funcionamos todos os dias, das 11h as 23h.',
        ),
        _StateDraft(
          name: 'Fazer pedido',
          message: 'Me diga o que voce deseja pedir para eu te ajudar.',
        ),
        _StateDraft(
          name: 'Atendente humano',
          message: 'Vou encaminhar voce para o atendimento humano.',
          requiresHandoff: true,
        ),
      ];
    }

    if (template == 'agendamento') {
      return <_StateDraft>[
        _StateDraft(
          name: 'Mensagem inicial',
          message: 'Oi! Voce quer marcar um horario?',
          expanded: true,
          options: <_OptionDraft>[
            _OptionDraft(
              label: 'Marcar horario',
              targetState: 'Marcar horario',
            ),
            _OptionDraft(
              label: 'Ver horarios disponiveis',
              targetState: 'Horarios disponiveis',
            ),
            _OptionDraft(
              label: 'Falar com atendente',
              targetState: 'Atendente humano',
            ),
          ],
        ),
        _StateDraft(
          name: 'Marcar horario',
          message: 'Perfeito. Qual dia e horario voce prefere?',
        ),
        _StateDraft(
          name: 'Horarios disponiveis',
          message: 'Temos horarios disponiveis de segunda a sexta.',
        ),
        _StateDraft(
          name: 'Atendente humano',
          message: 'Vou te encaminhar para um atendente finalizar o agendamento.',
          requiresHandoff: true,
        ),
      ];
    }

    return <_StateDraft>[
      _StateDraft(
        name: 'Mensagem inicial',
        message: 'Ola! Como posso ajudar voce hoje?',
        expanded: true,
        options: <_OptionDraft>[
          _OptionDraft(
            label: 'Falar com atendente',
            targetState: 'Atendente humano',
          ),
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
    var selectedTemplate = 'faq_loja';
    var startFromScratch = true;
    String? nameError;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Nova automa\u00e7\u00e3o',
            style: TextStyle(color: _kText, fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Defina um nome e escolha como quer comecar. Voce pode montar tudo do zero ou usar um modelo apenas para adiantar a estrutura inicial.',
                  style: TextStyle(color: _kMuted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: const TextStyle(color: _kText),
                  onChanged: (_) {
                    if (nameError != null) {
                      setDialogState(() => nameError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Nome da automa\u00e7\u00e3o',
                    hintText: 'ex: atendimento_loja',
                    errorText: nameError,
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
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kDanger),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _kDanger),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0x1F818CF8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.auto_fix_high_rounded,
                          color: _kAccentSoft,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Comecar do zero',
                              style: TextStyle(
                                color: _kText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              startFromScratch
                                  ? 'Vamos abrir uma automacao com uma etapa inicial vazia para voce definir mensagem, respostas e proximos passos do seu jeito.'
                                  : 'Desative esta opcao se quiser usar um modelo pronto como ponto de partida.',
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: startFromScratch,
                        activeTrackColor: _kAccent,
                        onChanged: (value) {
                          setDialogState(() => startFromScratch = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: startFromScratch
                      ? Container(
                          key: const ValueKey('scratch-mode'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _kSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                color: _kAccentSoft,
                                size: 18,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Voce vai comecar com uma etapa inicial em branco. Depois, no editor, basta preencher a mensagem, adicionar botoes e ligar a etapa aos proximos passos.',
                                  style: TextStyle(
                                    color: _kMuted,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          key: const ValueKey('template-mode'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _kSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Modelo inicial do fluxo',
                                style: TextStyle(
                                  color: _kText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Este dropdown serve apenas para adiantar o primeiro rascunho. Depois voce pode editar, remover ou renomear todas as etapas livremente.',
                                style: TextStyle(
                                  color: _kMuted,
                                  fontSize: 12,
                                  height: 1.45,
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
                                    style: const TextStyle(
                                      color: _kText,
                                      fontSize: 13,
                                    ),
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
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() => selectedTemplate = value);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _kCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kBorder),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: _kAccentSoft,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _templateLabel(selectedTemplate),
                                            style: const TextStyle(
                                              color: _kText,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _templateDescription(selectedTemplate),
                                            style: const TextStyle(
                                              color: _kMuted,
                                              fontSize: 12,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _kMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () async {
                final name = _normalizeFlowName(nameCtrl.text);
                if (name.isEmpty) {
                  setDialogState(
                    () => nameError = 'Informe um nome para continuar.',
                  );
                  return;
                }

                final states = startFromScratch
                    ? _buildBlankStates()
                    : _buildTemplateStates(selectedTemplate);
                Navigator.pop(ctx);
                setState(() {
                  _draft?.dispose();
                  _draft = _FlowDraft(
                    name: name,
                    description: startFromScratch
                        ? ''
                        : 'Automa\u00e7\u00e3o criada com assistente visual',
                    startState: states.isNotEmpty ? states.first.name : '',
                    states: states,
                  );
                });

                final draft = _draft;
                if (draft != null) {
                  _resetPreview(draft);
                  await _openCurrentDraftEditorDialog();
                }
              },
              child: Text(
                startFromScratch
                    ? 'Criar do zero'
                    : 'Usar modelo e criar',
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(nameCtrl.dispose);
  }

  void _showNewFlowDialog() {
    _showGuidedFlowDialog();
  }

  Future<void> _openFlowEditorDialog(String name) async {
    await _selectFlow(name);
    final draft = _draft;
    if (!mounted || draft == null) {
      return;
    }
    await _showAutomationDialog(
      title: 'Editar automa\u00e7\u00e3o',
      subtitle: draft.name,
      width: 1200,
      height: 820,
      child: _FlowEditorView(
        key: ValueKey('editor-${draft.name}'),
        draft: draft,
        saving: _saving,
        onSave: _save,
        autoOptionId: _autoOptionId,
        onChanged: _handleDraftChanged,
      ),
    );
  }

  Future<void> _openCurrentDraftEditorDialog() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    await _showAutomationDialog(
      title: 'Editar automa\u00e7\u00e3o',
      subtitle: draft.name,
      width: 1200,
      height: 820,
      child: _FlowEditorView(
        key: ValueKey('editor-${draft.name}'),
        draft: draft,
        saving: _saving,
        onSave: _save,
        autoOptionId: _autoOptionId,
        onChanged: _handleDraftChanged,
      ),
    );
  }

  Future<void> _openFlowTestDialog(String name) async {
    await _selectFlow(name);
    final draft = _draft;
    if (!mounted || draft == null) {
      return;
    }
    setState(() => _rightPanelTab = 0);
    _resetPreview(draft);
    await _showAutomationDialog(
      title: 'Testar automa\u00e7\u00e3o',
      subtitle: draft.name,
      width: 960,
      height: 760,
      child: _buildInsightsPanel(draft),
    );
  }

  Future<void> _showAutomationDialog({
    required String title,
    required String subtitle,
    required Widget child,
    required double width,
    required double height,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: _kSurface,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: _kMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _kDanger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      color: _kBg,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 20),
                  _buildAiConfigCard(),
                  const SizedBox(height: 20),
                  Expanded(child: _buildAutomationListCard()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: content,
    );
  }

  Widget _buildPageHeader() {
    final titleBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.embedded) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: _kMuted,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automa\u00e7\u00f5es',
              style: TextStyle(
                color: _kText,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Gerencie, edite e teste os fluxos do atendimento.',
              style: TextStyle(
                color: _kMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );

    final actionButton = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _kAccentSoft,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      onPressed: _isSystemAdminHomeContext ? null : _showNewFlowDialog,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Nova automa\u00e7\u00e3o'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: actionButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            actionButton,
          ],
        );
      },
    );
  }

  Widget _buildAutomationListCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suas automa\u00e7\u00f5es',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSystemAdminHomeContext
                      ? 'Selecione uma empresa para visualizar as automa\u00e7\u00f5es deste tenant.'
                      : 'Abra o menu de cada linha para editar ou testar uma automa\u00e7\u00e3o.',
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          _buildAutomationTableHeader(),
          const Divider(height: 1, color: _kBorder),
          Expanded(child: _buildAutomationListBody()),
        ],
      ),
    );
  }

  Widget _buildAutomationTableHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 14, 18, 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Automa\u00e7\u00e3o',
              style: TextStyle(
                color: _kSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'Descri\u00e7\u00e3o',
              style: TextStyle(
                color: _kSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Primeira etapa',
              style: TextStyle(
                color: _kSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildAutomationListBody() {
    if (_isSystemAdminHomeContext) {
      return _buildListPlaceholder(
        icon: Icons.apartment_rounded,
        title: 'Selecione uma empresa',
        message:
            'O tenant de sistema n\u00e3o possui automa\u00e7\u00f5es pr\u00f3prias. Escolha uma empresa em Clientes para editar ou testar fluxos.',
      );
    }

    if (_loadingFlows) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final rows = _buildAutomationRows();
    if (rows.isEmpty) {
      return _buildListPlaceholder(
        icon: Icons.account_tree_outlined,
        title: 'Nenhuma automa\u00e7\u00e3o criada',
        message:
            'Use o bot\u00e3o Nova automa\u00e7\u00e3o para criar o primeiro fluxo do atendimento.',
      );
    }

    return ListView(
      children: rows,
    );
  }

  List<Widget> _buildAutomationRows() {
    final rows = <Widget>[
      for (final flow in _flows)
        _FlowListItem(
          flow: flow,
          onEdit: () => _openFlowEditorDialog(flow.name),
          onTest: () => _openFlowTestDialog(flow.name),
        ),
    ];

    return rows;
  }

  Widget _buildListPlaceholder({
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
              child: Icon(icon, size: 28, color: _kAccentSoft),
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
              style: const TextStyle(
                color: _kMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiConfigCard() {
    final statusLabel = _isSystemAdminHomeContext
        ? 'Selecione uma empresa'
        : (_aiEnabled ? 'IA ativa' : 'IA desligada');

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _aiEnabled ? const Color(0xFF064E3B) : _kSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: _aiEnabled ? _kSuccess : _kMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'IA do atendimento',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: _aiEnabled ? _kSuccess : _kMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _aiEnabled,
            activeTrackColor: _kAccent,
            onChanged: _isSystemAdminHomeContext ? null : _toggleAi,
          ),
        ],
      ),
    );
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
                  'Testes',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
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
                        child: const Text('Teste'),
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
                        child: const Text('Mapa da automa\u00e7\u00e3o'),
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
                  'Envie uma mensagem para validar a conversa.',
                  style: TextStyle(color: _kMuted, fontSize: 12),
                ),
              ),
              _SmallBtn(
                icon: Icons.refresh_rounded,
                tooltip: 'Reiniciar simulacao',
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Text(
                    'Pr\u00e9via da automa\u00e7\u00e3o',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07111F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: _previewHistory.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhuma mensagem ainda.\nDigite abaixo para testar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _simulationScrollCtrl,
                            itemCount: _previewHistory.length,
                            itemBuilder: (_, index) {
                              final row = _previewHistory[index];
                              final isUser = row['role'] == 'user';
                              return Align(
                                alignment: isUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 250),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUser ? _kAccentSoft : _kCard,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft:
                                          Radius.circular(isUser ? 14 : 4),
                                      bottomRight:
                                          Radius.circular(isUser ? 4 : 14),
                                    ),
                                  ),
                                  child: Text(
                                    row['text'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                if (current != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: current.options
                        .where((option) => option.labelCtrl.text.trim().isNotEmpty)
                        .map(
                          (option) => OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kAccentSoft,
                              side: const BorderSide(color: _kAccentSoft),
                            ),
                            onPressed: option.targetState.trim().isEmpty
                                ? null
                                : () => _previewSelectOption(draft, option),
                            child: Text(option.labelCtrl.text.trim()),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _simulationInputCtrl,
                        style: const TextStyle(color: _kText, fontSize: 12),
                        onSubmitted: (_) =>
                            _runSimulationMessage(draft, _simulationInputCtrl.text),
                        decoration: InputDecoration(
                          hintText: 'Digite uma mensagem como cliente',
                          hintStyle:
                              const TextStyle(color: _kSubtle, fontSize: 12),
                          filled: true,
                          fillColor: _kInput,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
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
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccentSoft,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _sendingSimulation
                          ? null
                          : () =>
                              _runSimulationMessage(draft, _simulationInputCtrl.text),
                      icon: _sendingSimulation
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_sendingSimulation ? 'Enviando' : 'Enviar'),
                    ),
                  ],
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
                  color: _kText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
                  .where((option) => option.labelCtrl.text.trim().isNotEmpty)
                  .map(
                    (option) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Text('- ', style: TextStyle(color: _kSubtle)),
                          Expanded(
                            child: Text(
                              '[${option.labelCtrl.text.trim()}] -> ${option.targetState.isNotEmpty ? option.targetState : 'Sem destino'}',
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 12,
                              ),
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

enum _FlowListAction { edit, test }

class _FlowListItem extends StatefulWidget {
  const _FlowListItem({
    required this.flow,
    required this.onEdit,
    required this.onTest,
  });

  final FlowSummaryModel flow;
  final Future<void> Function() onEdit;
  final Future<void> Function() onTest;

  @override
  State<_FlowListItem> createState() => _FlowListItemState();
}

class _FlowListItemState extends State<_FlowListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final description = (flow.description ?? '').trim().isEmpty
      ? 'Sem descri\u00e7\u00e3o informada'
        : flow.description!.trim();
    final startState = (flow.startState ?? '').trim().isEmpty
      ? 'Nao definida'
        : flow.startState!.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        color: _hovered ? const Color(0xFF161F31) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(24, 16, 18, 16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: const Icon(
                      Icons.account_tree_outlined,
                      size: 18,
                      color: _kAccentSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      flow.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kMuted, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                startState,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kText, fontSize: 12),
              ),
            ),
            SizedBox(
              width: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<_FlowListAction>(
                    tooltip: 'A\u00e7\u00f5es da automa\u00e7\u00e3o',
                  color: _kCard,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: _kMuted,
                    size: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: _kBorder),
                  ),
                  onSelected: (action) async {
                    switch (action) {
                      case _FlowListAction.edit:
                        await widget.onEdit();
                        break;
                      case _FlowListAction.test:
                        await widget.onTest();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<_FlowListAction>(
                      value: _FlowListAction.edit,
                      child: Text('Editar', style: TextStyle(color: _kText)),
                    ),
                    PopupMenuItem<_FlowListAction>(
                      value: _FlowListAction.test,
                      child: Text('Testar', style: TextStyle(color: _kText)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallBtn extends StatefulWidget {
  const _SmallBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

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
  // Index of the node selected in the canvas; null = nothing selected
  int? _selectedIndex;
  // Whether the side panel is showing the quick-guide instead of a node config
  bool _showGuide = true;

  @override
  void initState() {
    super.initState();
    _autoLayoutIfNeeded();
  }

  // Give default positions to nodes that have none (Offset.zero)
  void _autoLayoutIfNeeded() {
    const double kNodeW = 220;
    const double kNodeH = 110;
    const double kColGap = 80;
    const double kRowGap = 40;
    const int kPerRow = 3;
    final states = widget.draft.states;
    for (var i = 0; i < states.length; i++) {
      if (states[i].position == Offset.zero) {
        final col = i % kPerRow;
        final row = i ~/ kPerRow;
        states[i].position = Offset(
          40.0 + col * (kNodeW + kColGap),
          40.0 + row * (kNodeH + kRowGap),
        );
      }
    }
  }

  void _addState() {
    final newName = 'Etapa ${widget.draft.states.length + 1}';
    final int newIndex = widget.draft.states.length;
    // Place new node below the last one
    Offset newPos = const Offset(40, 40);
    if (widget.draft.states.isNotEmpty) {
      final last = widget.draft.states.last;
      newPos = Offset(last.position.dx, last.position.dy + 150);
    }
    setState(() {
      widget.draft.states.add(
        _StateDraft(name: newName, expanded: false, position: newPos),
      );
      if (widget.draft.startState.isEmpty) {
        widget.draft.startState = newName;
      }
      _selectedIndex = newIndex;
      _showGuide = false;
    });
    widget.onChanged();
  }

  void _removeState(int index) {
    final removed = widget.draft.states[index];
    final removedName = removed.name;
    setState(() {
      widget.draft.states.removeAt(index);
      if (widget.draft.startState == removedName) {
        widget.draft.startState =
            widget.draft.states.isNotEmpty ? widget.draft.states.first.name : '';
      }
      if (_selectedIndex != null) {
        if (_selectedIndex == index) {
          _selectedIndex = null;
          _showGuide = true;
        } else if (_selectedIndex! > index) {
          _selectedIndex = _selectedIndex! - 1;
        }
      }
    });
    removed.dispose();
    widget.onChanged();
  }

  void _selectNode(int index) {
    setState(() {
      _selectedIndex = index;
      _showGuide = false;
    });
  }

  void _deselectNode() {
    if (_selectedIndex != null) {
      setState(() {
        _selectedIndex = null;
        _showGuide = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(draft),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Canvas area ────────────────────────────────────────
              Expanded(
                child: draft.states.isEmpty
                    ? _buildEmptyCanvas()
                    : _FlowCanvas(
                        draft: draft,
                        selectedIndex: _selectedIndex,
                        onSelectNode: _selectNode,
                        onNodeMoved: (i, pos) {
                          setState(() => draft.states[i].position = pos);
                        },
                        onAddState: _addState,
                        onChanged: () {
                          setState(() {});
                          widget.onChanged();
                        },
                        onDeselectNode: _deselectNode,
                      ),
              ),
              // ── Side panel ─────────────────────────────────────────
              Container(
                width: 360,
                decoration: const BoxDecoration(
                  color: _kSurface,
                  border: Border(left: BorderSide(color: _kBorder)),
                ),
                child: _buildSidePanel(draft),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidePanel(_FlowDraft draft) {
    if (_showGuide || _selectedIndex == null || _selectedIndex! >= draft.states.length) {
      return _buildGuidePanel();
    }
    final index = _selectedIndex!;
    final state = draft.states[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _kCard,
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0x1F818CF8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _kAccentSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.name.isEmpty ? 'Configurar etapa' : state.name,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _SmallBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Excluir etapa',
                onTap: () => _removeState(index),
              ),
              const SizedBox(width: 4),
              _SmallBtn(
                icon: Icons.close_rounded,
                tooltip: 'Fechar painel',
                onTap: () => setState(() {
                  _selectedIndex = null;
                  _showGuide = true;
                }),
              ),
            ],
          ),
        ),
        // Panel body — scrollable config
        Expanded(
          child: _StateCard(
            state: state,
            stepNumber: index + 1,
            isStartState: draft.startState == state.name,
            stateNames: draft.stateNames,
            autoOptionId: widget.autoOptionId,
            onToggleExpanded: (_) {},
            onDelete: () => _removeState(index),
            onChanged: () {
              setState(() {});
              widget.onChanged();
            },
            sidePanelMode: true,
          ),
        ),
      ],
    );
  }

  Widget _buildGuidePanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_rounded, color: _kAccentSoft, size: 20),
              SizedBox(width: 10),
              Text(
                'Editor visual de fluxo',
                style: TextStyle(
                  color: _kText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Cada bloco no canvas representa uma etapa do seu fluxo de conversa. Clique em um bloco para configurar seu conte\u00fado e conex\u00f5es.',
            style: TextStyle(color: _kMuted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 20),
          _buildGuidePanelTip(
            icon: Icons.open_with_rounded,
            title: 'Arrastar blocos',
            desc: 'Segure e arraste qualquer bloco para reorganizar o layout do diagrama.',
          ),
          _buildGuidePanelTip(
            icon: Icons.arrow_forward_rounded,
            title: 'Conex\u00f5es autom\u00e1ticas',
            desc: 'As setas aparecem automaticamente conforme voc\u00ea configura bot\u00f5es e regras de texto dentro de cada etapa.',
          ),
          _buildGuidePanelTip(
            icon: Icons.touch_app_rounded,
            title: 'Configurar etapa',
            desc: 'Clique em qualquer bloco para abrir a configura\u00e7\u00e3o completa aqui neste painel lateral.',
          ),
          _buildGuidePanelTip(
            icon: Icons.add_box_outlined,
            title: 'Nova etapa',
            desc: 'Use o bot\u00e3o \u201cAdicionar etapa\u201d no canto inferior do canvas para inserir uma nova etapa.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: _addState,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Adicionar etapa'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidePanelTip({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: Icon(icon, color: _kAccentSoft, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _kText, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        color: _kMuted, fontSize: 11, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCanvas() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_tree_outlined, size: 52, color: _kSubtle),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma etapa criada ainda',
            style: TextStyle(color: _kMuted, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crie a primeira etapa para come\u00e7ar a montar o fluxo visual.',
            style: TextStyle(color: _kSubtle, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            onPressed: _addState,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Criar primeira etapa'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(_FlowDraft draft) {
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
              label: 'Nome da automa\u00e7\u00e3o',
              child: _DarkField(
                controller: draft.nameCtrl,
                hint: 'Ex: Atendimento da loja',
                onChanged: widget.onChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: _LabeledField(
              label: 'Descri\u00e7\u00e3o (opcional)',
              child: _DarkField(
                controller: draft.descCtrl,
                hint: 'Descreva o objetivo desta automa\u00e7\u00e3o',
                onChanged: widget.onChanged,
              ),
            ),
          ),
          const SizedBox(width: 14),
          _LabeledField(
            label: 'Primeira etapa',
            child: Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: draft.stateNames.contains(draft.startState)
                      ? draft.startState
                      : (draft.stateNames.isEmpty ? null : draft.stateNames.first),
                  dropdownColor: _kCard,
                  isDense: true,
                  style: const TextStyle(color: _kText, fontSize: 13),
                  hint: const Text(
                    'Selecione',
                    style: TextStyle(color: _kSubtle, fontSize: 13),
                  ),
                  items: draft.stateNames
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => draft.startState = value);
                    widget.onChanged();
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: widget.saving ? null : widget.onSave,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(widget.saving ? 'Salvando...' : 'Salvar automa\u00e7\u00e3o'),
            ),
          ),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// CANVAS — visual block diagram editor
// ═══════════════════════════════════════════════════════════════════════════

class _FlowCanvas extends StatefulWidget {
  const _FlowCanvas({
    required this.draft,
    required this.selectedIndex,
    required this.onSelectNode,
    required this.onNodeMoved,
    required this.onAddState,
    required this.onChanged,
    this.onDeselectNode,
  });

  final _FlowDraft draft;
  final int? selectedIndex;
  final ValueChanged<int> onSelectNode;
  final void Function(int index, Offset position) onNodeMoved;
  final VoidCallback onAddState;
  final VoidCallback onChanged;
  final VoidCallback? onDeselectNode;

  @override
  State<_FlowCanvas> createState() => _FlowCanvasState();
}

class _FlowCanvasState extends State<_FlowCanvas> {
  static const double kNodeW = 220.0;
  static const double kNodeH = 110.0;

  // Pan offset for the infinite canvas
  Offset _panOffset = Offset.zero;
  Offset? _panStart;
  Offset? _panStartOffset;
  double _zoom = 1.0;
  static const double _kZoomMin = 0.25;
  static const double _kZoomMax = 2.0;
  static const double _kZoomStep = 0.15;

  // Which node is being dragged
  int? _draggingIndex;

  void _onDragStart(int index) {
    setState(() => _draggingIndex = index);
    widget.onSelectNode(index);
  }

  // delta is in screen pixels; divide by zoom to get canvas units
  void _onDragDelta(Offset screenDelta) {
    if (_draggingIndex == null) return;
    final state = widget.draft.states[_draggingIndex!];
    widget.onNodeMoved(_draggingIndex!, state.position + screenDelta / _zoom);
  }

  void _onDragEnd() {
    setState(() => _draggingIndex = null);
  }

  void _zoomIn() => setState(() => _zoom = (_zoom + _kZoomStep).clamp(_kZoomMin, _kZoomMax));
  void _zoomOut() => setState(() => _zoom = (_zoom - _kZoomStep).clamp(_kZoomMin, _kZoomMax));
  void _zoomReset() => setState(() => _zoom = 1.0);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Listener(
        onPointerSignal: (event) {
          // Scroll wheel zoom
          if (event is PointerScrollEvent) {
            setState(() {
              final factor = event.scrollDelta.dy > 0 ? -_kZoomStep : _kZoomStep;
              _zoom = (_zoom + factor).clamp(_kZoomMin, _kZoomMax);
            });
          }
        },
        onPointerMove: (event) {
          if (event.buttons == 4) {
            // middle-mouse pan
            setState(() => _panOffset += event.delta / _zoom);
          }
        },
        child: GestureDetector(
          onTap: () => widget.onDeselectNode?.call(),
          onPanStart: (details) {
            if (_draggingIndex != null) return;
            _panStart = details.localPosition;
            _panStartOffset = _panOffset;
          },
          onPanUpdate: (details) {
            if (_draggingIndex != null) return;
            if (_panStart != null) {
              setState(() =>
                  _panOffset = _panStartOffset! + (details.localPosition - _panStart!) / _zoom);
            }
          },
          onPanEnd: (_) {
            _panStart = null;
            _panStartOffset = null;
          },
          child: Container(
            color: const Color(0xFF0A1628),
            child: Stack(
              children: [
                // Grid dots background
                Positioned.fill(child: CustomPaint(painter: _GridPainter(zoom: _zoom))),
                // Arrow painter (screen coordinates — zoom-aware)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FlowArrowPainter(
                      states: widget.draft.states,
                      panOffset: _panOffset,
                      zoom: _zoom,
                      nodeW: kNodeW,
                      nodeH: kNodeH,
                      selectedIndex: widget.selectedIndex,
                    ),
                  ),
                ),
                // Node blocks (screen coordinates — fixes drag boundary at zoom < 1)
                ...List.generate(widget.draft.states.length, (i) {
                  final state = widget.draft.states[i];
                  final screenPos = (state.position + _panOffset) * _zoom;
                  final isSelected = widget.selectedIndex == i;
                  final isStart = widget.draft.startState == state.name;
                  return Positioned(
                    left: screenPos.dx,
                    top: screenPos.dy,
                    child: Transform.scale(
                      scale: _zoom,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: kNodeW,
                        child: _CanvasNode(
                          state: state,
                          stepNumber: i + 1,
                          isSelected: isSelected,
                          isStart: isStart,
                          isDragging: _draggingIndex == i,
                          onTap: () => widget.onSelectNode(i),
                          onDragStart: () => _onDragStart(i),
                          onDragDelta: _onDragDelta,
                          onDragEnd: _onDragEnd,
                        ),
                      ),
                    ),
                  );
                }),
                // Zoom controls (bottom-right)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: _buildZoomControls(),
                ),
                // Add node button (bottom-left)
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: _buildAddBtn(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomBtn(
            icon: Icons.remove_rounded,
            tooltip: 'Diminuir zoom',
            onTap: _zoomOut,
          ),
          InkWell(
            onTap: _zoomReset,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                '${(_zoom * 100).round()}%',
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _ZoomBtn(
            icon: Icons.add_rounded,
            tooltip: 'Aumentar zoom',
            onTap: _zoomIn,
          ),
        ],
      ),
    );
  }

  Widget _buildAddBtn() {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: widget.onAddState,
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Adicionar etapa'),
    );
  }
}

// ── Canvas node ────────────────────────────────────────────────────────────

class _CanvasNode extends StatefulWidget {
  const _CanvasNode({
    required this.state,
    required this.stepNumber,
    required this.isSelected,
    required this.isStart,
    required this.isDragging,
    required this.onTap,
    required this.onDragStart,
    required this.onDragDelta,
    required this.onDragEnd,
  });

  final _StateDraft state;
  final int stepNumber;
  final bool isSelected;
  final bool isStart;
  final bool isDragging;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragDelta;
  final VoidCallback onDragEnd;

  @override
  State<_CanvasNode> createState() => _CanvasNodeState();
}

class _CanvasNodeState extends State<_CanvasNode> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final title = state.name.isEmpty ? 'Sem nome' : state.name;
    final msg = state.message.isEmpty ? 'Sem mensagem' : state.message;
    final optCount = state.options.where((o) => o.labelCtrl.text.trim().isNotEmpty).length;
    final trCount = state.transitions.where((t) => t.keywordCtrl.text.trim().isNotEmpty).length;

    final borderColor = widget.isSelected
        ? _kAccentSoft
        : (_hovered ? const Color(0xFF4B5563) : _kBorder);
    final bgColor = widget.isSelected
        ? const Color(0xFF1A2640)
        : (_hovered ? const Color(0xFF1F2D42) : _kCard);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onTap: widget.onTap,
        onPanStart: (_) => widget.onDragStart(),
        onPanUpdate: (d) => widget.onDragDelta(d.delta),
        onPanEnd: (_) => widget.onDragEnd(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: widget.isSelected ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: widget.isSelected
                    ? const Color(0x407C8CFF)
                    : const Color(0x40000000),
                blurRadius: widget.isDragging ? 24 : 10,
                offset: Offset(0, widget.isDragging ? 10 : 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? const Color(0x1F818CF8)
                      : const Color(0xFF111827),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? const Color(0x337C8CFF)
                            : _kSurface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _kBorder),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.stepNumber}',
                        style: TextStyle(
                          color: widget.isSelected ? _kAccentSoft : _kMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isSelected ? _kAccentSoft : _kText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.isStart)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF065F46),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'IN\u00cdCIO',
                          style: TextStyle(
                            color: _kSuccess,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Message preview
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Text(
                  msg,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
              // Footer chips
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (optCount > 0)
                      _NodeChip(
                        icon: Icons.smart_button_rounded,
                        label: '$optCount bot\u00e3o${optCount != 1 ? "s" : ""}',
                        color: _kAccent,
                      ),
                    if (trCount > 0)
                      _NodeChip(
                        icon: Icons.alt_route_rounded,
                        label: '$trCount regra${trCount != 1 ? "s" : ""}',
                        color: const Color(0xFF10B981),
                      ),
                    if (state.requiresHandoff)
                      const _NodeChip(
                        icon: Icons.support_agent_rounded,
                        label: 'Handoff',
                        color: Color(0xFFF59E0B),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeChip extends StatelessWidget {
  const _NodeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Arrow painter ──────────────────────────────────────────────────────────

class _FlowArrowPainter extends CustomPainter {
  _FlowArrowPainter({
    required this.states,
    required this.panOffset,
    required this.zoom,
    required this.nodeW,
    required this.nodeH,
    this.selectedIndex,
  });

  final List<_StateDraft> states;
  final Offset panOffset;
  final double zoom;
  final double nodeW;
  final double nodeH;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4B6BFF)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arrowPaint = Paint()
      ..color = const Color(0xFF4B6BFF)
      ..style = PaintingStyle.fill;

    final String? selectedName = selectedIndex != null && selectedIndex! < states.length
        ? states[selectedIndex!].name
        : null;

    for (var srcIdx = 0; srcIdx < states.length; srcIdx++) {
      final src = states[srcIdx];
      final targets = <String>{
        ...src.options.map((o) => o.targetState).whereType<String>(),
        ...src.transitions.map((t) => t.targetState).whereType<String>(),
      };

      for (final targetName in targets) {
        if (targetName.isEmpty) continue;
        // If a node is selected, show only arrows connected to it
        if (selectedName != null) {
          final isSrcSelected = src.name == selectedName;
          final isDstSelected = targetName == selectedName;
          if (!isSrcSelected && !isDstSelected) continue;
        }
        final dstIndex = states.indexWhere((s) => s.name == targetName);
        if (dstIndex < 0) continue;
        final dst = states[dstIndex];

        // Compute screen-space positions (zoom-aware)
        final from = Offset(
          (src.position.dx + panOffset.dx + nodeW) * zoom,
          (src.position.dy + panOffset.dy + nodeH / 2) * zoom,
        );
        final to = Offset(
          (dst.position.dx + panOffset.dx) * zoom,
          (dst.position.dy + panOffset.dy + nodeH / 2) * zoom,
        );

        final dx = (to.dx - from.dx).abs().clamp(60.0 * zoom, 200.0 * zoom);
        final c1 = Offset(from.dx + dx * 0.6, from.dy);
        final c2 = Offset(to.dx - dx * 0.6, to.dy);

        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
        canvas.drawPath(path, paint);
        _drawArrowhead(canvas, arrowPaint, to, c2);
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Paint paint, Offset tip, Offset controlPoint) {
    final raw = tip - controlPoint;
    final len = raw.distance;
    if (len == 0) return;
    final dir = raw / len;
    final size = 8.0 * zoom;
    final perp = Offset(-dir.dy, dir.dx);
    final left = tip - dir * size + perp * (size * 0.4);
    final right = tip - dir * size - perp * (size * 0.4);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlowArrowPainter old) => true;
}

// ── Grid background ────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  const _GridPainter({this.zoom = 1.0});
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A2030);
    final step = (28.0 * zoom).clamp(8.0, 80.0);
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.zoom != zoom;
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 16, color: _kMuted),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// End of canvas
// ═══════════════════════════════════════════════════════════════════════════

class _StateCard extends StatefulWidget {
  const _StateCard({
    required this.state,
    required this.stepNumber,
    required this.isStartState,
    required this.stateNames,
    required this.autoOptionId,
    required this.onToggleExpanded,
    required this.onDelete,
    required this.onChanged,
    this.sidePanelMode = false,
  });

  final _StateDraft state;
  final int stepNumber;
  final bool isStartState;
  final List<String> stateNames;
  final String Function(String label, int index) autoOptionId;
  final ValueChanged<bool> onToggleExpanded;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final bool sidePanelMode;

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

  void _removeOption(int index) {
    widget.state.options.removeAt(index).dispose();
    setState(() {});
    widget.onChanged();
  }

  void _addTransition() {
    setState(() => widget.state.transitions.add(_TransitionDraft()));
    widget.onChanged();
  }

  void _removeTransition(int index) {
    widget.state.transitions.removeAt(index).dispose();
    setState(() {});
    widget.onChanged();
  }

  int _filledOptionsCount(_StateDraft state) {
    return state.options
        .where((option) => option.labelCtrl.text.trim().isNotEmpty)
        .length;
  }

  int _filledTransitionsCount(_StateDraft state) {
    return state.transitions
        .where((transition) => transition.keywordCtrl.text.trim().isNotEmpty)
        .length;
  }

  Widget _buildStageSelect({
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: const Text(
            'Selecionar etapa',
            style: TextStyle(color: _kSubtle, fontSize: 12),
          ),
          isExpanded: true,
          dropdownColor: _kCard,
          style: const TextStyle(color: _kText, fontSize: 12),
          items: widget.stateNames
              .map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEmptySectionState({
    Key? key,
    required IconData icon,
    required String message,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _kSubtle, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _kSubtle,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicsSection(_StateDraft state) {
    return _EditorPanel(
      icon: Icons.chat_bubble_outline_rounded,
      title: '1. Conteudo da etapa',
      description:
          'Defina o nome interno desta etapa e a mensagem principal que o cliente vai receber ao entrar nela.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledField(
            label: 'Nome da etapa',
            child: _DarkField(
              controller: state.nameCtrl,
              hint: 'Ex: Mensagem inicial',
              onChanged: () {
                setState(() {});
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Mensagem enviada ao usuario',
            child: TextField(
              controller: state.msgCtrl,
              onChanged: (_) {
                setState(() {});
                widget.onChanged();
              },
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(color: _kText, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ex: Ola! Como posso ajudar voce hoje?',
                hintStyle: const TextStyle(color: _kSubtle, fontSize: 13),
                filled: true,
                fillColor: _kInput,
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
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(_StateDraft state) {
    return _EditorPanel(
      icon: Icons.settings_suggest_outlined,
      title: '4. Acoes adicionais',
      description:
          'Use estes recursos so quando esta etapa precisar sair do bot e seguir para atendimento humano ou para uma integracao.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kInput,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encaminhar para atendente humano',
                        style: TextStyle(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ative quando esta etapa deve parar o fluxo automatico e transferir a conversa.',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: state.requiresHandoff,
                  activeTrackColor: _kAccent,
                  onChanged: (value) {
                    setState(() => state.requiresHandoff = value);
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LabeledField(
            label: 'Acao no sistema (opcional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DarkField(
                  controller: state.hookActionCtrl,
                  hint: 'Ex: consultar_pedido',
                  onChanged: widget.onChanged,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Preencha somente se esta etapa precisar chamar uma integracao externa.',
                  style: TextStyle(color: _kSubtle, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // In side-panel mode, always show expanded content in a scrollable list
    if (widget.sidePanelMode) {
      return _buildSidePanelContent(widget.state);
    }

    final state = widget.state;
    final title = state.nameCtrl.text.trim().isEmpty
        ? 'Nome da etapa'
        : state.nameCtrl.text.trim();
    final previewText = state.msgCtrl.text.trim().isEmpty
        ? 'Defina a mensagem principal desta etapa para orientar o cliente.'
        : state.msgCtrl.text.trim();
    final buttonsCount = _filledOptionsCount(state);
    final transitionsCount = _filledTransitionsCount(state);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: state.expanded ? _kAccentSoft : _kBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x40000000),
              blurRadius: _hovered ? 14 : 10,
              offset: Offset(0, _hovered ? 6 : 4),
            ),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => widget.onToggleExpanded(!state.expanded),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(11),
                  bottom:
                      state.expanded ? Radius.zero : const Radius.circular(11),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
                  decoration: BoxDecoration(
                    color: state.expanded ? const Color(0xFF243044) : _kCard,
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(11),
                      bottom: state.expanded
                          ? Radius.zero
                          : const Radius.circular(11),
                    ),
                    border: state.expanded
                        ? const Border(bottom: BorderSide(color: _kBorder))
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: state.expanded
                              ? const Color(0x1F818CF8)
                              : _kSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${widget.stepNumber}',
                          style: const TextStyle(
                            color: _kText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _kText,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (widget.isStartState) ...[
                                  const SizedBox(width: 10),
                                  const _StateSummaryChip(
                                    icon: Icons.play_arrow_rounded,
                                    label: 'Etapa inicial',
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              previewText,
                              maxLines: state.expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _StateSummaryChip(
                                  icon: Icons.list_alt_rounded,
                                  label: '$buttonsCount botoes',
                                ),
                                _StateSummaryChip(
                                  icon: Icons.keyboard_rounded,
                                  label: '$transitionsCount regras de texto',
                                ),
                                if (state.requiresHandoff)
                                  const _StateSummaryChip(
                                    icon: Icons.support_agent_rounded,
                                    label: 'Encaminha para humano',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        children: [
                          Icon(
                            state.expanded
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.chevron_right_rounded,
                            color: _kMuted,
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          Tooltip(
                            message: 'Remover esta etapa',
                            child: InkWell(
                              onTap: widget.onDelete,
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: _kDanger,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (state.expanded)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBasicsSection(state),
                      const SizedBox(height: 16),
                      _buildOptionsSection(state),
                      const SizedBox(height: 16),
                      _buildTransitionsSection(state),
                      const SizedBox(height: 16),
                      _buildActionsSection(state),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsSection(_StateDraft state) {
    return _EditorPanel(
      icon: Icons.list_alt_rounded,
      title: '2. Botoes e escolhas rapidas',
      description:
          'Use botoes quando quiser mostrar opcoes clicaveis para o cliente. Cada botao precisa apontar para a proxima etapa.',
      action: _DashedActionButton(
        icon: Icons.add_rounded,
        label: 'Adicionar botao',
        onTap: _addOption,
      ),
      child: AnimatedSwitcher(
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
        child: state.options.isEmpty
            ? _buildEmptySectionState(
                key: const ValueKey('options-empty'),
                icon: Icons.touch_app_outlined,
                message:
                    'Nenhum botao configurado ainda. Adicione um botao para oferecer escolhas rapidas ao cliente.',
              )
            : Column(
                key: const ValueKey('options-list'),
                children: List.generate(state.options.length, (index) {
                  final option = state.options[index];
                  return Container(
                    margin: EdgeInsets.only(
                      bottom: index == state.options.length - 1 ? 0 : 12,
                    ),
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
                            _StateSummaryChip(
                              icon: Icons.touch_app_outlined,
                              label: 'Botao ${index + 1}',
                            ),
                            const Spacer(),
                            Tooltip(
                              message: 'Remover botao',
                              child: InkWell(
                                onTap: () => _removeOption(index),
                                borderRadius: BorderRadius.circular(6),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: _kSubtle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 620;
                            final textField = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Texto do botao',
                                  style: TextStyle(
                                    color: _kSubtle,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _DarkField(
                                  controller: option.labelCtrl,
                                  hint: 'Ex: Prazo de entrega',
                                  onChanged: () {
                                    setState(() {});
                                    widget.onChanged();
                                  },
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Identificador automatico: ${widget.autoOptionId(option.labelCtrl.text.trim(), index)}',
                                  style: const TextStyle(
                                    color: _kSubtle,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            );
                            final targetField = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Para qual etapa ele leva?',
                                  style: TextStyle(
                                    color: _kSubtle,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildStageSelect(
                                  value: widget.stateNames.contains(option.targetState)
                                      ? option.targetState
                                      : null,
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() => option.targetState = value);
                                    widget.onChanged();
                                  },
                                ),
                              ],
                            );

                            if (stacked) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  textField,
                                  const SizedBox(height: 12),
                                  targetField,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: textField),
                                const SizedBox(width: 12),
                                Expanded(child: targetField),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ),
      ),
    );
  }

  Widget _buildTransitionsSection(_StateDraft state) {
    return _EditorPanel(
      icon: Icons.keyboard_rounded,
      title: '3. Regras para texto digitado',
      description:
          'Use quando o cliente pode escrever algo em vez de clicar em um botao. Cada regra envia a conversa para outra etapa.',
      action: _DashedActionButton(
        icon: Icons.add_rounded,
        label: 'Adicionar regra',
        onTap: _addTransition,
      ),
      child: state.transitions.isEmpty
          ? _buildEmptySectionState(
              icon: Icons.keyboard_rounded,
              message:
                  'Nenhuma regra de texto configurada. Pode deixar vazio se este passo usar somente botoes.',
            )
          : Column(
              children: List.generate(state.transitions.length, (index) {
                final transition = state.transitions[index];
                return Container(
                  margin: EdgeInsets.only(
                    bottom: index == state.transitions.length - 1 ? 0 : 12,
                  ),
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
                          _StateSummaryChip(
                            icon: Icons.subdirectory_arrow_right_rounded,
                            label: 'Regra ${index + 1}',
                          ),
                          const Spacer(),
                          Tooltip(
                            message: 'Remover regra',
                            child: InkWell(
                              onTap: () => _removeTransition(index),
                              borderRadius: BorderRadius.circular(6),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: _kSubtle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 620;
                          final keywordField = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Quando o cliente escrever',
                                style: TextStyle(
                                  color: _kSubtle,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: transition.keywordCtrl,
                                onChanged: (_) {
                                  setState(() {});
                                  widget.onChanged();
                                },
                                style: const TextStyle(
                                  color: _kText,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  hintText: 'Ex: entrega',
                                  hintStyle: const TextStyle(
                                    color: _kSubtle,
                                    fontSize: 13,
                                  ),
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
                                ),
                              ),
                            ],
                          );
                          final targetField = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Para qual etapa deve ir?',
                                style: TextStyle(
                                  color: _kSubtle,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _buildStageSelect(
                                value:
                                    widget.stateNames.contains(transition.targetState)
                                        ? transition.targetState
                                        : null,
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() => transition.targetState = value);
                                  widget.onChanged();
                                },
                              ),
                            ],
                          );

                          if (stacked) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                keywordField,
                                const SizedBox(height: 12),
                                targetField,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: keywordField),
                              const SizedBox(width: 12),
                              Expanded(child: targetField),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }

  Widget _buildSidePanelContent(_StateDraft state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildBasicsSection(state),
        const SizedBox(height: 12),
        _buildOptionsSection(state),
        const SizedBox(height: 12),
        _buildTransitionsSection(state),
        const SizedBox(height: 12),
        _buildActionsSection(state),
        const SizedBox(height: 20),
      ],
    );
  }
}

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
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );

    const dash = 6.0;
    const gap = 4.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
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

class _StateSummaryChip extends StatelessWidget {
  const _StateSummaryChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSubCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x1F818CF8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _kAccentSoft, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        height: 1.45,
                      ),
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
  const _DarkField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

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
          fillColor: _kSubCard,
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
    );

  }

}
