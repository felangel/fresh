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
    @required this.tokenHeader,
    @required TokenStorage<T> tokenStorage,
    @required RefreshToken<T> refreshToken,
    ShouldRefresh shouldRefresh,
    Dio httpClient,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _tokenStorage = tokenStorage,
        _refreshToken = refreshToken,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _httpClient = httpClient ?? Dio() {
    _tokenStorage.read().then((token) {
      _token = token;
      _authenticationStatus = token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    });
  }

  static Fresh<OAuth2Token> auth2Token({
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

  static final StreamController _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  final Dio _httpClient;
  final TokenStorage<T> _tokenStorage;
  final TokenHeaderBuilder<T> tokenHeader;
  final ShouldRefresh _shouldRefresh;
  final RefreshToken<T> _refreshToken;

  T _token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  /// If the provided token is null, the `AuthenticationStatus` will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  ///
  /// This method should be called after making a successful token request
  /// from the custom `RefreshInterceptor` implementation.
  Future<void> setToken(T token) async {
    await _tokenStorage.write(token);
    final authenticationStatus = token == null
        ? AuthenticationStatus.unauthenticated
        : AuthenticationStatus.authenticated;
    _authenticationStatus = authenticationStatus;
    _controller.add(authenticationStatus);
    _token = token;
  }

  @override
  Future<dynamic> onRequest(RequestOptions options) async {
    final token = await _getToken();
    final data = tokenHeader(token);

    if (token != null) {
      (options.headers ?? <String, String>{}).addAll(data);
    }
    return options;
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (_token == null || !_shouldRefresh(response)) {
      return response;
    }

    return _tryRefresh(response);
  }

  @override
  Future<dynamic> onError(DioError err) async {
    final response = err.response;
    if (_token == null || !_shouldRefresh(response)) {
      return err;
    }
    return _tryRefresh(response);
  }

  Future<Response> _tryRefresh(Response response) async {
    T refreshedToken;
    try {
      refreshedToken = await _refreshToken(_token, _httpClient);
    } on RevokeTokenException catch (_) {
      await _onRevokeTokenException();
      return response;
    }
    await _tokenStorage.write(refreshedToken);
    _token = refreshedToken;

    return await _httpClient.request(
      response.request.path,
      cancelToken: response.request.cancelToken,
      data: response.request.data,
      onReceiveProgress: response.request.onReceiveProgress,
      onSendProgress: response.request.onSendProgress,
      queryParameters: response.request.queryParameters,
      options: response.request..headers.addAll(tokenHeader(_token)),
    );
  }

  static bool _defaultShouldRefresh(Response response) {
    return response?.statusCode == 401;
  }

  Future<T> _getToken() async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    final token = await _tokenStorage.read();
    final authenticationStatus = token != null
        ? AuthenticationStatus.authenticated
        : AuthenticationStatus.unauthenticated;
    _authenticationStatus = authenticationStatus;
    _controller.add(authenticationStatus);

    _token = token;
    return _token;
  }

  Future<void> _onRevokeTokenException() async {
    await _tokenStorage.delete();
    _token = null;
    _authenticationStatus = AuthenticationStatus.unauthenticated;
    _controller.add(AuthenticationStatus.unauthenticated);
  }
}
