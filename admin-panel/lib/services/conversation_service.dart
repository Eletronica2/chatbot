import '../models/conversation.dart';
import '../models/flow_state.dart';
import '../models/message.dart';
import 'api_client.dart';

class ConversationService {
  ConversationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Encode path segments for `tenant:phone` ids but keep `:`.
  /// Full [Uri.encodeComponent] turns `:` into `%3A`; FastAPI then sees no
  /// colon and returns Invalid conversation_id.
  static String conversationPathId(String conversationId) {
    return conversationId.split(':').map(Uri.encodeComponent).join(':');
  }

  Future<List<Conversation>> fetchConversations() async {
    final data = await _apiClient.get('/api/v1/conversations');
    return Conversation.listFromJson(data);
  }

  Future<List<ChatMessageModel>> fetchMessages(String conversationId) async {
    final encodedConversationId = conversationPathId(conversationId);
    final data = await _apiClient.get('/api/v1/conversations/$encodedConversationId/messages');
    return ChatMessageModel.listFromJson(data);
  }

  Future<FlowStateModel?> fetchFlowState(String conversationId) async {
    final encodedConversationId = conversationPathId(conversationId);
    final data = await _apiClient.get('/api/v1/conversations/$encodedConversationId/flow');
    if (data is Map<String, dynamic>) {
      return FlowStateModel.fromJson(data);
    }
    return null;
  }

  Future<void> sendReply(String conversationId, String text) async {
    final encodedConversationId = conversationPathId(conversationId);
    await _apiClient.post(
      '/api/v1/conversations/$encodedConversationId/reply',
      body: {'text': text},
    );
  }
}

final conversationService = ConversationService(apiClient: apiClient);
