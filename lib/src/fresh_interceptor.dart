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
  });

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
abstract class Token {
  /// {@macro token}
  const Token();
}

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

/// {@template fresh_interceptor}
/// A Dio HTTP Interceptor for automatic token refresh.
/// Requires a concrete implementation of [TokenStorage]
/// and handles transparently refreshing/caching tokens.
///
/// In most cases, [FreshInterceptor] should be extended by a
/// custom RefreshInterceptor implementation and the `refreshToken`
/// method must be implemented.
///
/// ```dart
/// class RefreshInterceptor extends FreshInterceptor<OAuth2Token> {
///   // Must provide a concrete implementation of `TokenStorage` to super.
///   ApiClient() : super(InMemoryTokenStorage());
///
///   @override
///   Future<OAuth2Token> refreshToken(token, client) async {
///     // Make a token refresh request using the current token
///     // and the provided client and return a new token.
///   }
/// }
/// ```
/// {@endtemplate}
abstract class FreshInterceptor<T extends Token> extends Interceptor {
  /// {@macro fresh_interceptor}
  FreshInterceptor(TokenStorage tokenStorage)
      : assert(tokenStorage != null),
        _tokenStorage = tokenStorage {
    _tokenStorage.read().then((token) {
      _token = token;
      _authenticationStatus = token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    });
  }

  static final Dio _httpClient = Dio();
  static final StreamController _controller =
      StreamController<AuthenticationStatus>()
        ..add(AuthenticationStatus.initial);

  final TokenStorage<T> _tokenStorage;

  T _token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus => _controller.stream;

  /// Returns the desired header which will be added to all outgoing requests.
  /// Defaults to:
  /// ```dart
  /// {
  ///   'authorization': '${token.tokenType} ${token.accessToken}'
  /// }
  /// ```
  /// if token is of type [OAuth2Token].
  ///
  /// This method must be overridden if using a non [OAuth2Token]
  /// otherwise an `UnimplementedError` will be thrown.
  Map<String, String> tokenHeader(T token) {
    if (token is OAuth2Token) {
      return {
        'authorization': '${token.tokenType} ${token.accessToken}',
      };
    }
    throw UnimplementedError();
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
      (options.headers ?? <String, String>{}).addAll(tokenHeader(token));
    }
    return options;
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (_token == null || !shouldRefresh(response)) {
      return response;
    }

    T refreshedToken;
    try {
      refreshedToken = await refreshToken(_token, _httpClient);
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

  /// Must be overridden and is responsible for returning a new token
  /// given the current token and an http client instance.
  ///
  /// `refreshToken` will be called when `shouldRefresh` returns `true`.
  ///
  /// If a refresh fails, a [RevokeTokenException] should be thrown in order
  /// to invalidate the current token.
  Future<T> refreshToken(T token, Dio httpClient);

  /// Returns a `bool` which determines whether `refreshToken` should be called
  /// based on the provided `Response`.
  ///
  /// By default `shouldRefresh` returns `true`
  /// if the response has a 401 status code.
  bool shouldRefresh(Response response) {
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
