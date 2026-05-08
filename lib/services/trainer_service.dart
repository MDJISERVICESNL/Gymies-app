import 'api_client.dart';
import 'gymies_api.dart';

/// Legacy helper kept for compatibility.
///
/// Note: this file previously used `http`, `json` and a `getToken()` function
/// that no longer exist in this codebase, which broke `flutter analyze` / build.
Stream<bool> checkTrainerStory(int trainerId) async* {
  final apiClient = ApiClient();
  final api = GymiesApi(apiClient: apiClient);
  yield await api.hasStories(trainerId);
}
