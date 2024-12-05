import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';

class PhotosRequestFailureException implements Exception {}

class JsonplaceholderClient {
  JsonplaceholderClient({Dio? httpClient})
      : _httpClient = (httpClient ?? Dio())
          ..options.baseUrl = 'https://jsonplaceholder.typicode.com'
          ..interceptors.add(_fresh)
          ..interceptors.add(
            LogInterceptor(request: false, responseHeader: false),
          );

  static var _refreshCount = 0;
  static final _fresh = Fresh.oAuth2<OAuth2Token>(
    tokenStorage: InMemoryOAuth2TokenStorage<OAuth2Token>(),
    refreshToken: (token, client) async {
      print('refreshing token...');
      await Future<void>.delayed(const Duration(seconds: 1));
      if (Random().nextInt(3) == 0) {
        print('token revoked!');
        throw RevokeTokenException();
      }
      print('token refreshed!');
      _refreshCount++;
      return OAuth2Token(
        accessToken: 'access_token_$_refreshCount',
        refreshToken: 'refresh_token_$_refreshCount',
        expiresIn: 30,
      );
    },
    shouldRefresh: (_) => Random().nextInt(3) == 0,
  );

  final Dio _httpClient;

  Stream<AuthenticationStatus> get authenticationStatus =>
      _fresh.authenticationStatus;

  Future<void> authenticate({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _fresh.setToken(
      const OAuth2Token(
        accessToken: 'initial_access_token',
        refreshToken: 'initial_refresh_token',
        expiresIn: 30, // expires every 30 seconds
      ),
    );
  }

  Future<void> unauthenticate() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _fresh.setToken(null);
  }

  Future<List<Photo>> photos() async {
    final response = await _httpClient.get<dynamic>('/photos');

    if (response.statusCode != 200) {
      throw PhotosRequestFailureException();
    }

    return (response.data as List)
        .map((dynamic item) => Photo.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
