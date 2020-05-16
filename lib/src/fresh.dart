import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:meta/meta.dart';

/// An Exception that should be thrown when overriding `refreshToken` if the
/// refresh fails and should result in a force-logout.
class RevokeTokenException implements Exception {}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// {@endtemplate}
class OAuth2Token implements Token {
  /// {macro oauth2_token}
  const OAuth2Token({
    @required this.accessToken,
    this.tokenType = 'bearer',
    this.expiresIn,
    this.refreshToken,
    this.scope,
  }) : assert(accessToken != null);

  /// The access token string as issued by the authorization server.
  final String accessToken;

  /// The type of token this is, typically just the string “bearer”.
  final String tokenType;

  /// If the access token expires, the server should reply
  /// with the duration of time the access token is granted for.
  final int expiresIn;

  /// Token which applications can use to obtain another access token.
  final String refreshToken;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String scope;
}

/// {@template token}
/// Generic Token Interface
/// {@endtemplate}
abstract class Token {}

/// Enum representing the current authentication status of the application.
enum AuthenticationStatus {
  /// The status before the true `AuthenticationStatus` has been determined.
  initial,

  /// The status when the application is not authenticated.
  unauthenticated,

  /// The status when the application is authenticated.
  authenticated
}

/// An interface which must be implemented to
/// read, write, and delete the `Token`.
abstract class TokenStorage<T extends Token> {
  /// Returns the stored token asynchronously.
  Future<T> read();

  /// Saves the provided [token] asynchronously.
  Future<void> write(T token);

  /// Deletes the stored token asynchronously.
  Future<void> delete();
}

typedef TokenHeaderBuilder<T extends Token> = Map<String, String> Function(
  T token,
);

typedef ShouldRefreshFunction = bool Function(Response response);

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
class Fresh<T extends Token> extends Interceptor {
  /// {@macro fresh}
  Fresh({
    @required TokenStorage tokenStorage,
    @required RefreshToken<T> refreshToken,
    TokenHeaderBuilder tokenHeader,
    ShouldRefreshFunction shouldRefresh,
    Dio httpClient,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _tokenStorage = tokenStorage,
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader ?? _defaultTokenHeader,
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

  static final StreamController _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  final Dio _httpClient;
  final TokenStorage<T> _tokenStorage;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefreshFunction _shouldRefresh;
  final RefreshToken<T> _refreshToken;

  T _token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus => _controller.stream;

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
    _controller.add(
      token == null
          ? AuthenticationStatus.unauthenticated
          : AuthenticationStatus.authenticated,
    );
    _token = token;
  }

  @override
  Future<dynamic> onRequest(RequestOptions options) async {
    final token = await _getToken();
    if (token != null) {
      (options.headers ?? <String, String>{}).addAll(_tokenHeader(token));
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
      options: response.request..headers.addAll(_tokenHeader(_token)),
    );
  }

  static Map<String, String> _defaultTokenHeader(Token token) {
    if (token is OAuth2Token) {
      return {
        'authorization': '${token.tokenType} ${token.accessToken}',
      };
    }
    throw UnimplementedError();
  }

  static bool _defaultShouldRefresh(Response response) {
    return response.statusCode == 401;
  }

  Future<T> _getToken() async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    final token = await _tokenStorage.read();
    _controller.add(
      token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated,
    );
    _token = token;
    return _token;
  }

  Future<void> _onRevokeTokenException() async {
    await _tokenStorage.delete();
    _token = null;
    _controller.add(AuthenticationStatus.unauthenticated);
  }
}
