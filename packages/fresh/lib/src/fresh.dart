import 'dart:async';

import 'package:meta/meta.dart';

/// An Exception that should be thrown when overriding `refreshToken` if the
/// refresh fails and should result in a force-logout.
class RevokeTokenException implements Exception {}

/// An exception that should be thrown when
/// an invalid token is passed to the `setToken` function.
class InvalidTokenException implements Exception {}

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

class FreshController<T> {
  FreshController({@required TokenStorage<T> tokenStorage})
      : _tokenStorage = tokenStorage {
    _tokenStorage.read().then(updateStatus);
  }

  final StreamController<AuthenticationStatus> _controller =
      StreamController<AuthenticationStatus>.broadcast();
  //   ..add(AuthenticationStatus.initial);

  final StreamController<T> _tokenController = StreamController<T>.broadcast();

  final TokenStorage<T> _tokenStorage;
  T token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;
  AuthenticationStatus get authenticationStatusValue => _authenticationStatus;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  /// Returns a `Stream<T>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<T> get currentToken async* {
    yield token;
    yield* _tokenController.stream;
  }

  /// Sets the internal [token] to the provided [token] and updates
  /// the `AuthenticationStatus` to `AuthenticationStatus.authenticated`
  /// If the provided token is null, the `removeToken` will be thrown.
  ///
  /// This method should be called after making a successful token request
  /// from the custom `RefreshInterceptor` implementation.
  Future<void> setToken(T token) async {
    if (token == null) {
      removeToken();
    } else {
      await _tokenStorage.write(token);
      updateStatus(token);
    }
  }

  Future<void> updateStatus(T token) async {
    _authenticationStatus = token != null
        ? AuthenticationStatus.authenticated
        : AuthenticationStatus.unauthenticated;
    _controller.add(_authenticationStatus);
    this.token = token;
    _tokenController.add(token);
  }

  /// Delete the storaged [token]. and emit the
  /// `AuthenticationStatus.unauthenticated` if authenticationStatus
  /// not is `AuthenticationStatus.unauthenticated`
  /// This method should be called when the token is no longer valid.
  Future<void> revokeToken() async {
    _tokenStorage.delete();
    if (authenticationStatus != AuthenticationStatus.unauthenticated) {
      _authenticationStatus = AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    }
  }

  /// Removes the internal [token]. and updates the `AuthenticationStatus`
  /// to `AuthenticationStatus.unauthenticated`.
  /// This method should be called when you want to log off the user.
  Future<void> removeToken() async {
    await _tokenStorage.delete();
    updateStatus(null);
  }
}
