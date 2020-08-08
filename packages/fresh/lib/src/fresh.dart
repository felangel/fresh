import 'dart:async';

import 'package:meta/meta.dart';

/// An Exception that should be thrown when overriding `refreshToken` if the
/// refresh fails and should result in a force-logout.
class RevokeTokenException implements Exception {}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// {@endtemplate}
class OAuth2Token {
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
abstract class TokenStorage<T> {
  /// Returns the stored token asynchronously.
  Future<T> read();

  /// Saves the provided [token] asynchronously.
  Future<void> write(T token);

  /// Deletes the stored token asynchronously.
  Future<void> delete();
}

/// Function responsible for building the token header(s) give a [token].
typedef TokenHeaderBuilder<T> = Map<String, String> Function(
  T token,
);

/// A [TokenStorage] implementation that keeps the token in memory.
class InMemoryTokenStorage<T> implements TokenStorage<T> {
  T _token;

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<T> read() async {
    return _token;
  }

  @override
  Future<void> write(T token) async {
    _token = token;
  }
}

/// {@template fresh_mixin}
/// A mixin which handles core token refresh functionality.
/// {@endtemplate}
mixin FreshMixin<T> {
  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  TokenStorage<T> _tokenStorage;

  T _token;

  final StreamController<AuthenticationStatus> _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  set tokenStorage(TokenStorage<T> tokenStorage) {
    _tokenStorage = tokenStorage..read().then(_updateStatus);
  }

  /// Returns the current token.
  Future<T> get token async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    await authenticationStatus.first;
    return _token;
  }

  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  ///
  /// If the provided token is null, the `AuthenticationStatus` will be updated
  /// to `unauthenticated` and the token will be removed from storage, otherwise
  /// it will be updated to `authenticated`and save to storage.
  Future<void> setToken(T token) async {
    if (token == null) return clearToken();
    await _tokenStorage.write(token);
    _updateStatus(token);
  }

  /// Delete the storaged [token]. and emit the
  /// `AuthenticationStatus.unauthenticated` if authenticationStatus
  /// not is `AuthenticationStatus.unauthenticated`
  /// This method should be called when the token is no longer valid.
  Future<void> revokeToken() async {
    await _tokenStorage.delete();
    if (_authenticationStatus != AuthenticationStatus.unauthenticated) {
      _authenticationStatus = AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    }
  }

  Future<void> clearToken() async {
    await _tokenStorage.delete();
    _updateStatus(null);
  }

  /// Closes Fresh StreamController.
  ///
  /// [setToken] and [clearToken] must not be called after this method.
  ///
  /// Calling this method more than once is allowed, but does nothing.
  Future<void> close() => _controller.close();

  /// Update the internal [token] and updates the
  /// `AuthenticationStatus` accordingly.
  ///
  /// If the provided token is null, the `AuthenticationStatus` will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  void _updateStatus(T token) {
    _authenticationStatus = token != null
        ? AuthenticationStatus.authenticated
        : AuthenticationStatus.unauthenticated;
    _token = token;
    _controller.add(_authenticationStatus);
  }
}
