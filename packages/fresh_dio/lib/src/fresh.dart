import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:meta/meta.dart';

typedef ShouldRefresh = bool Function(Response response);

typedef RefreshToken<T> = Future<T> Function(T token, Dio httpClient);

/// {@template fresh}
/// A Dio Interceptor for automatic token refresh.
/// Requires a concrete implementation of [TokenStorage] and [RefreshToken].
/// Handles transparently refreshing/caching tokens.
///
/// ```dart
/// dio.interceptors.add(
///   Fresh<OAuth2Token>(
///     tokenStorage: InMemoryTokenStorage(),
///     refreshToken: (token, client) async {...},
///   ),
/// );
/// ```
/// {@endtemplate}
class Fresh<T> extends Interceptor {
  /// {@macro fresh}
  Fresh({
    @required TokenHeaderBuilder<T> tokenHeader,
    @required TokenStorage<T> tokenStorage,
    @required RefreshToken<T> refreshToken,
    ShouldRefresh shouldRefresh,
    Dio httpClient,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        assert(tokenHeader != null),
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _tokenStorage = tokenStorage,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _freshController = FreshController<T>(tokenStorage: tokenStorage),
        _httpClient = httpClient ?? Dio();

  /// A Dio Interceptor for automatic token refresh.
  /// Requires a concrete implementation of [TokenStorage<OAuth2Token>]
  ///  and [RefreshToken<OAuth2Token>].
  /// Handles transparently refreshing/caching tokens.
  ///
  /// A constructor that returns a Fresh interceptor that uses the
  /// `OAuth2Token` token, the standard token class.
  ///
  /// ```dart
  /// dio.interceptors.add(
  ///   Fresh.oAuth2Token(
  ///     tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
  ///     refreshToken: (token, client) async {...},
  ///   ),
  /// );
  /// ```
  static Fresh<OAuth2Token> oAuth2Token({
    @required TokenStorage<OAuth2Token> tokenStorage,
    @required RefreshToken<OAuth2Token> refreshToken,
    ShouldRefresh shouldRefresh,
    TokenHeaderBuilder<OAuth2Token> tokenHeader,
  }) {
    return Fresh<OAuth2Token>(
        refreshToken: refreshToken,
        tokenStorage: tokenStorage,
        shouldRefresh: shouldRefresh,
        tokenHeader: tokenHeader ??
            (token) {
              return {
                'authorization': '${token.tokenType} ${token.accessToken}',
              };
            });
  }

  final Dio _httpClient;
  final FreshController<T> _freshController;
  final TokenStorage<T> _tokenStorage;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;
  final RefreshToken<T> _refreshToken;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus =>
      _freshController.authenticationStatus;

  /// Sets the internal [token] to the provided [token] and updates
  /// the `AuthenticationStatus` to `AuthenticationStatus.authenticated`
  /// If the provided token is null, the `removeToken` will be thrown.
  ///
  /// This method should be called after making a successful token request
  /// from the custom `RefreshInterceptor` implementation.
  Future<void> setToken(T token) async {
    await _freshController.setToken(token);
  }

  /// Removes the internal [token]. and updates the `AuthenticationStatus`
  /// to `AuthenticationStatus.unauthenticated`.
  /// This method should be called when you want to log off the user.
  Future<void> removeToken() async {
    await _freshController.removeToken();
  }

  @override
  Future<dynamic> onRequest(RequestOptions options) async {
    final token = await _getToken();
    final data = _tokenHeader(token);

    if (token != null) {
      (options.headers ?? <String, String>{}).addAll(data);
    }
    return options;
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (_freshController.token == null || !_shouldRefresh(response)) {
      return response;
    }

    return _tryRefresh(response);
  }

  @override
  Future<dynamic> onError(DioError err) async {
    final response = err.response;
    if (_freshController.token == null || !_shouldRefresh(response)) {
      return err;
    }
    return _tryRefresh(response);
  }

  Future<Response> _tryRefresh(Response response) async {
    T refreshedToken;
    try {
      refreshedToken = await _refreshToken(_freshController.token, _httpClient);
    } on RevokeTokenException catch (_) {
      await _freshController.removeToken();
      return response;
    }
    await _tokenStorage.write(refreshedToken);
    _freshController.token = refreshedToken;

    return await _httpClient.request(
      response.request.path,
      cancelToken: response.request.cancelToken,
      data: response.request.data,
      onReceiveProgress: response.request.onReceiveProgress,
      onSendProgress: response.request.onSendProgress,
      queryParameters: response.request.queryParameters,
      options: response.request
        ..headers.addAll(_tokenHeader(_freshController.token)),
    );
  }

  static bool _defaultShouldRefresh(Response response) {
    return response?.statusCode == 401;
  }

  Future<T> _getToken() async {
    if (_freshController.authenticationStatusValue !=
        AuthenticationStatus.initial) return _freshController.token;
    final token = await _tokenStorage.read();
    _freshController.updateStatus(token);
    return token;
  }
}
