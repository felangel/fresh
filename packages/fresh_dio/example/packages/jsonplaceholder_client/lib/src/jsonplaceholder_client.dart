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
  static final _fresh = Fresh.oAuth2(
    tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
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
      );
    },
    shouldRefresh: (_) => Random().nextInt(3) == 0,
    shouldRefreshBeforeRequest: (token) async {
      print('Checking token validity before request...');
      final now = currentUnixTime();
      final issuedAt = await fetchIssuedAt();
      if (token?.expiresIn != null && issuedAt != null) {
        return (issuedAt + token!.expiresIn!) < now;
      }
      return false;
    },
  );

  final Dio _httpClient;

  Stream<AuthenticationStatus> get authenticationStatus =>
      _fresh.authenticationStatus;

  Future<void> authenticate({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    final issuedAt = currentUnixTime();
    await storeIssuedAt(issuedAt);
    await _fresh.setToken(
      const OAuth2Token(
        accessToken: 'initial_access_token',
        refreshToken: 'initial_refresh_token',
        expiresIn: 60,
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

  /// Returns the current Unix time in seconds (since January 1, 1970, UTC).
  static int currentUnixTime() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Simulate storing issuedAt when a token is set or refreshed.
  static int? _storedIssuedAt;

  static Future<void> storeIssuedAt(int issuedTime) async {
    print('Storing issuedAt: $issuedTime');
    _storedIssuedAt = issuedTime;
  }

  /// Simulate fetching issuedAt from storage.
  static Future<int?> fetchIssuedAt() async {
    print('Fetching issuedAt...');
    return _storedIssuedAt;
  }
}
