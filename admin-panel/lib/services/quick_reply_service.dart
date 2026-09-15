import '../models/quick_reply.dart';
import 'api_client.dart';

class QuickReplyService {
  QuickReplyService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<QuickReply>> listQuickReplies() async {
    final data = await _apiClient.get('/api/v1/quick-replies');
    return QuickReply.listFromJson(data);
  }

  Future<QuickReply> createQuickReply({
    required String title,
    required String shortcut,
    required String content,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/quick-replies',
      body: {
        'title': title.trim(),
        'shortcut': _normalizeShortcut(shortcut),
        'content': content.trim(),
      },
    );
    return QuickReply.fromJson(data as Map<String, dynamic>);
  }

  Future<QuickReply> updateQuickReply({
    required String id,
    String? title,
    String? shortcut,
    String? content,
  }) async {
    final data = await _apiClient.patch(
      '/api/v1/quick-replies/$id',
      body: {
        if (title != null) 'title': title.trim(),
        if (shortcut != null) 'shortcut': _normalizeShortcut(shortcut),
        if (content != null) 'content': content.trim(),
      },
    );
    return QuickReply.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteQuickReply(String id) async {
    await _apiClient.delete('/api/v1/quick-replies/$id');
  }

  String _normalizeShortcut(String raw) {
    var value = raw.trim();
    if (value.startsWith('/')) value = value.substring(1);
    return value.toLowerCase();
  }
}

final quickReplyService = QuickReplyService(apiClient: apiClient);
