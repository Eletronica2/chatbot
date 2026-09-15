import '../models/conversation_group.dart';
import 'api_client.dart';

class ConversationGroupService {
  ConversationGroupService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<ConversationGroup>> listGroups() async {
    final data = await _apiClient.get('/api/v1/conversation-groups');
    return ConversationGroup.listFromJson(data);
  }

  Future<ConversationGroup> createGroup({
    required String name,
    String? description,
    List<String>? memberUserIds,
  }) async {
    final data = await _apiClient.post(
      '/api/v1/conversation-groups',
      body: {
        'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (memberUserIds != null) 'member_user_ids': memberUserIds,
      },
    );
    return ConversationGroup.fromJson(data as Map<String, dynamic>);
  }

  Future<ConversationGroup> updateGroup({
    required String id,
    String? name,
    String? description,
    List<String>? memberUserIds,
  }) async {
    final data = await _apiClient.patch(
      '/api/v1/conversation-groups/$id',
      body: {
        if (name != null) 'name': name.trim(),
        if (description != null) 'description': description.trim(),
        if (memberUserIds != null) 'member_user_ids': memberUserIds,
      },
    );
    return ConversationGroup.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteGroup(String id) async {
    await _apiClient.delete('/api/v1/conversation-groups/$id');
  }
}

final conversationGroupService =
    ConversationGroupService(apiClient: apiClient);
