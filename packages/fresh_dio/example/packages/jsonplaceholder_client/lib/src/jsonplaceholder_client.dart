import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';
import 'package:meta/meta.dart';

class PhotosRequestFailureException implements Exception {}

class JsonplaceholderClient {
  JsonplaceholderClient({Dio httpClient})
      : _httpClient = (httpClient ?? Dio())
          ..options.baseUrl = 'https://jsonplaceholder.typicode.com'
          ..interceptors.add(_fresh);

  static var _refreshCount = 0;
  static final _fresh = Fresh.auth2Token(
    tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
    refreshToken: (token, client) async {
      print('refreshing token...');
      await Future.delayed(const Duration(seconds: 1));
      if (Random().nextInt(3) == 0) {
        print('token revoked!');
        throw RevokeTokenException();
      }
      print('token refreshed!');
      _refreshCount++;
      return OAuth2Token(
        accessToken: 'access_token_$_refreshCount',
        refreshToken: 'refresh_token_$_refreshCount',
      );
    },
    shouldRefresh: (_) => Random().nextInt(3) == 0,
  );

  final Dio _httpClient;

  Stream<AuthenticationStatus> get authenticationStatus =>
      _fresh.authenticationStatus;

  Future<void> authenticate({
    @required String username,
    @required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    await _fresh.setToken(
      OAuth2Token(
        accessToken: 'initial_access_token',
        refreshToken: 'initial_refresh_token',
      ),
    );
  }

  Future<void> unauthenticate() async {
    await Future.delayed(const Duration(seconds: 1));
    await _fresh.setToken(null);
  }

  Future<List<Photo>> photos() async {
    final response = await _httpClient.get('/photos');

    if (response.statusCode != 200) {
      throw PhotosRequestFailureException();
    }

    return (response.data as List).map((item) => Photo.fromJson(item)).toList();
  }
}
