/// Regras de conteúdo para modelos WhatsApp (espelho do backend).
class WaTemplateRules {
  static final _varRe = RegExp(r'\{\{(\d+|[a-zA-Z_][a-zA-Z0-9_]*)\}\}');
  static final _emojiRe = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}'
    r'\u{1F900}-\u{1F9FF}]',
    unicode: true,
  );
  static final _markdownRe = RegExp(r'(\*[^*]+\*|_[^_]+_|~[^~]+~|```)');

  static List<String> variables(String text) =>
      _varRe.allMatches(text).map((m) => m.group(1) ?? '').where((e) => e.isNotEmpty).toList();

  static String? validateHeader(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final t = text.trim();
    if (t.length > 60) return 'Cabeçalho: máximo 60 caracteres.';
    if (t.contains('\n') || t.contains('\r')) return 'Cabeçalho: não permite quebra de linha.';
    if (_emojiRe.hasMatch(t)) return 'Cabeçalho: emojis não são permitidos.';
    if (_markdownRe.hasMatch(t)) return 'Cabeçalho: formatação (*, _, ~, ```) não é permitida.';
    if (variables(t).length > 1) return 'Cabeçalho: no máximo 1 variável.';
    return null;
  }

  static String? validateFooter(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final t = text.trim();
    if (t.length > 60) return 'Rodapé: máximo 60 caracteres.';
    if (t.contains('\n') || t.contains('\r')) return 'Rodapé: não permite quebra de linha.';
    if (_emojiRe.hasMatch(t)) return 'Rodapé: emojis não são permitidos.';
    if (variables(t).isNotEmpty) return 'Rodapé: variáveis não são permitidas.';
    if (_markdownRe.hasMatch(t)) return 'Rodapé: formatação não é permitida.';
    return null;
  }

  static String? validateBody(String text, {List<String> examples = const []}) {
    if (text.trim().isEmpty) return 'Corpo: obrigatório.';
    if (text.length > 1024) return 'Corpo: máximo 1.024 caracteres.';
    final vars = variables(text);
    if (vars.isNotEmpty) {
      final nums = vars.where((v) => int.tryParse(v) != null).map(int.parse).toList()..sort();
      if (nums.length == vars.length) {
        final expect = List.generate(nums.length, (i) => i + 1);
        if (nums.join(',') != expect.join(',')) {
          return 'Corpo: use variáveis numeradas sequenciais ({{1}}, {{2}}…).';
        }
      }
      final ex = examples.where((e) => e.trim().isNotEmpty).toList();
      if (ex.length != vars.length) {
        return 'Corpo: informe ${vars.length} exemplo(s) para aprovação (${ex.length} informado(s)), separados por |.';
      }
    }
    return null;
  }

  static String? validateButtonLabel(String text, {String field = 'Botão'}) {
    final t = text.trim();
    if (t.isEmpty) return '$field: texto obrigatório.';
    if (t.length > 25) return '$field: máximo 25 caracteres.';
    if (_emojiRe.hasMatch(t)) return '$field: emojis não são permitidos.';
    if (variables(t).isNotEmpty) return '$field: variáveis não são permitidas.';
    if (_markdownRe.hasMatch(t)) return '$field: formatação não é permitida.';
    return null;
  }
}