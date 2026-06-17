class WhatsAppTemplateModel {
  const WhatsAppTemplateModel({
    this.templateId,
    required this.name,
    required this.language,
    required this.category,
    required this.status,
    this.bodyText,
  });

  final String? templateId;
  final String name;
  final String language;
  final String category;
  final String status;
  final String? bodyText;

  factory WhatsAppTemplateModel.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplateModel(
      templateId: json['template_id'] as String?,
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? '',
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      bodyText: json['body_text'] as String?,
    );
  }
}
