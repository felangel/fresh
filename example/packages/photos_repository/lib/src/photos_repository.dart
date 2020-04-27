import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';

class PhotosRequestFailureException implements Exception {}

class PhotosRepository {
  PhotosRepository(JsonplaceholderClient jsonPlaceholderClient)
      : _jsonplaceholderClient = jsonPlaceholderClient;

  final JsonplaceholderClient _jsonplaceholderClient;

  Future<List<String>> getPhotos() async {
    try {
      final photosResponse = await _jsonplaceholderClient.photos();
      return photosResponse.map((photo) => photo.thumbnailUrl).toList();
    } on Exception catch (_) {
      throw PhotosRequestFailureException();
    }
  }
}
