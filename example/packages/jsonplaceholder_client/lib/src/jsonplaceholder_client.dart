import 'dart:convert';
import 'dart:html';

import 'package:api_client/api_client.dart';
import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';
import 'package:meta/meta.dart';

class PhotosRequestFailureException implements Exception {}

class JsonplaceholderClient {
  JsonplaceholderClient({ApiClient apiClient})
      : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Stream<AuthenticationStatus> get authenticationStatus =>
      _apiClient.authenticationStatus;

  Future<void> authenticate({
    @required String username,
    @required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    await _apiClient.setToken(
      OAuth2Token(
        accessToken: 'initial_access_token',
        refreshToken: 'initial_refresh_token',
      ),
    );
  }

  Future<void> unauthenticate() async {
    await Future.delayed(const Duration(seconds: 1));
    await _apiClient.setToken(null);
  }

  Future<List<Photo>> photos() async {
    final response = await _apiClient.get(
      Uri.https('jsonplaceholder.typicode.com', '/photos'),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw PhotosRequestFailureException();
    }

    final body = json.decode(response.body);
    return (body as List).map((item) => Photo.fromJson(item)).toList();
  }
}
