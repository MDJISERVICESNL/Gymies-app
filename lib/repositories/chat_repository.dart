import '../services/gymies_api.dart';

/// ChatRepository — abstractie laag voor chat/conversatie API calls.
///
/// Centraliseert alle chat-gerelateerde API calls zodat screens
/// niet direct met GymiesApi hoeven te praten.
class ChatRepository {
  ChatRepository({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  /// Haal conversaties op voor de ingelogde gebruiker.
  Future<List<Map<String, dynamic>>> getConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.get('conversations', queryParams: {
      'limit': '$limit',
      'offset': '$offset',
    });
    final data = response['data'] ?? response['conversations'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Haal berichten op voor een conversatie.
  Future<List<Map<String, dynamic>>> getMessages(
    int conversationId, {
    int limit = 50,
    String? before, // cursor-based pagination
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (before != null) params['before'] = before;

    final response = await _api.get(
      'conversations/$conversationId/messages',
      queryParams: params,
    );
    final data = response['data'] ?? response['messages'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Stuur een bericht in een conversatie.
  Future<Map<String, dynamic>> sendMessage(
    int conversationId,
    String message,
  ) async {
    return await _api.post('conversations/$conversationId/messages', {
      'message': message,
    });
  }

  /// Start een nieuwe conversatie met een gebruiker.
  Future<Map<String, dynamic>> startConversation(int otherUserId, {String? initialMessage}) async {
    final body = <String, dynamic>{'user_id': otherUserId};
    if (initialMessage != null) body['message'] = initialMessage;
    return await _api.post('conversations', body);
  }

  /// Markeer conversatie als gelezen.
  Future<void> markAsRead(int conversationId) async {
    await _api.post('conversations/$conversationId/read', {});
  }
}
