class WhatsAppTemplateButtonModel {
  const WhatsAppTemplateButtonModel({required this.type, required this.text});

  final String type;
  final String text;

  factory WhatsAppTemplateButtonModel.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplateButtonModel(
      type: json['type']?.toString() ?? 'QUICK_REPLY',
      text: json['text']?.toString() ?? '',
    );
  }
}

class WhatsAppTemplateModel {
  const WhatsAppTemplateModel({
    this.templateId,
    required this.name,
    required this.language,
    required this.category,
    required this.status,
    this.rejectedReason,
    this.bodyText,
    this.headerFormat,
    this.headerText,
    this.footerText,
    this.bodyExamples = const [],
    this.buttons = const [],
  });

  final String? templateId;
  final String name;
  final String language;
  final String category;
  final String status;
  final String? rejectedReason;
  final String? bodyText;
  final String? headerFormat;
  final String? headerText;
  final String? footerText;
  final List<String> bodyExamples;
  final List<WhatsAppTemplateButtonModel> buttons;

  factory WhatsAppTemplateModel.fromJson(Map<String, dynamic> json) {
    final rawButtons = json['buttons'];
    final buttons = rawButtons is List
        ? rawButtons
            .whereType<Map<String, dynamic>>()
            .map(WhatsAppTemplateButtonModel.fromJson)
            .toList()
        : <WhatsAppTemplateButtonModel>[];
    final rawExamples = json['body_examples'];
    final examples = rawExamples is List
        ? rawExamples.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    return WhatsAppTemplateModel(
      templateId: json['template_id'] as String?,
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? '',
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      rejectedReason: json['rejected_reason'] as String?,
      bodyText: json['body_text'] as String?,
      headerFormat: json['header_format'] as String?,
      headerText: json['header_text'] as String?,
      footerText: json['footer_text'] as String?,
      bodyExamples: examples,
      buttons: buttons,
    );
  }

  WhatsAppTemplateModel copyWithStatus({
    required String status,
    String? rejectedReason,
  }) {
    return WhatsAppTemplateModel(
      templateId: templateId,
      name: name,
      language: language,
      category: category,
      status: status,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      bodyText: bodyText,
      headerFormat: headerFormat,
      headerText: headerText,
      footerText: footerText,
      bodyExamples: bodyExamples,
      buttons: buttons,
    );
  }
}