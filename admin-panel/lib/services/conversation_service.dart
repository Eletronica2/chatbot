import '../models/conversation.dart';
import '../models/flow_state.dart';
import '../models/message.dart';
import 'api_client.dart';

class ConversationService {
  ConversationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<List<Conversation>> fetchConversations() async {
    final data = await _apiClient.get('/api/v1/conversations');
    return Conversation.listFromJson(data);
  }

  Future<List<ChatMessageModel>> fetchMessages(String conversationId) async {
    final encodedConversationId = Uri.encodeComponent(conversationId);
    final data = await _apiClient.get('/api/v1/conversations/$encodedConversationId/messages');
    return ChatMessageModel.listFromJson(data);
  }

  Future<FlowStateModel?> fetchFlowState(String conversationId) async {
    final encodedConversationId = Uri.encodeComponent(conversationId);
    final data = await _apiClient.get('/api/v1/conversations/$encodedConversationId/flow');
    if (data is Map<String, dynamic>) {
      return FlowStateModel.fromJson(data);
    }
    return null;
  }

  Future<void> sendReply(String conversationId, String text) async {
    final encodedConversationId = Uri.encodeComponent(conversationId);
    await _apiClient.post(
      '/api/v1/conversations/$encodedConversationId/reply',
      body: {'text': text},
    );
  }
}

final conversationService = ConversationService(apiClient: apiClient);

