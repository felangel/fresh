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

/// {@template token}
/// It is no longer necessary to implement Token interface.
///
/// Before:
/// ```dart
/// class CustomToken implements Token {}
/// ```
/// Just create your Token class without implementing anything.
///
/// Currently:
/// ```dart
/// class CustomToken {}
/// ```
///
/// This will be removed in the next versions.
/// {@endtemplate}
@deprecated
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

/// An interface that must be implemented to create an interceptor
/// that transparently updates / caches tokens.
abstract class FreshBase<T> implements Sink<T> {
  /// {@template  freshBaseSetToken}
  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  ///
  /// If the provided token is null, the `AuthenticationStatus` will be updated
  /// to `unauthenticated` and the token will be removed from storage, otherwise
  /// it will be updated to `authenticated`and save to storage.
  ///
  /// This method should be called after making a successful token request
  /// from the custom `RefreshInterceptor` implementation.
  ///
  ///
  /// If you want to remove the token, set as null and update
  ///`AuthenticationStatus` to `unauthenticated`
  /// you can use `removeToken()` instead of `setToken(null)`.
  ///
  ///
  /// Using `removeToken()` or `setToken(null)` the behavior will be the same,
  /// but using `removeToken()` is more clearer.
  /// {@endtemplate}
  Future<void> setToken(T token);

  /// Removes the internal [token] from the storage, sets the internal [token]
  ///  as null and updates the `AuthenticationStatus` to `unauthenticated`.
  /// This method should be called when you want to log off the user.
  Future<void> removeToken();

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus;

  /// Returns a `Stream<T>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<T> get currentToken;
}

/// {@template controller}
///A token controller for handles update / caching tokens transparently.
/// {@endtemplate}
class FreshController<T> implements FreshBase<T> {
  /// {@macro controller}
  FreshController({@required TokenStorage<T> tokenStorage})
      : _tokenStorage = tokenStorage {
    _tokenStorage.read().then(updateStatus);
  }

  final StreamController<AuthenticationStatus> _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  final StreamController<T> _tokenController = StreamController<T>.broadcast();

  final TokenStorage<T> _tokenStorage;

  /// Current internal token.
  T token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  /// Return the current internal `AuthenticationStatus`.
  AuthenticationStatus get authenticationStatusValue => _authenticationStatus;

  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  Stream<T> get currentToken async* {
    yield token;
    yield* _tokenController.stream;
  }

  Future<void> setToken(T token) async {
    if (token == null) {
      await removeToken();
    } else {
      await _tokenStorage.write(token);
      updateStatus(token);
    }
  }

  /// Update the internal [token] and updates the
  /// `AuthenticationStatus` accordingly.
  ///
  /// If the provided token is null, the `AuthenticationStatus` will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  void updateStatus(T token) {
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
    await _tokenStorage.delete();
    if (authenticationStatus != AuthenticationStatus.unauthenticated) {
      _authenticationStatus = AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    }
  }

  Future<void> removeToken() async {
    await _tokenStorage.delete();
    updateStatus(null);
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  ///
  /// If the provided token is null, the `AuthenticationStatus` will be updated
  /// to `unauthenticated` and the token will be removed from storage, otherwise
  /// it will be updated to `authenticated`and save to storage.
  ///
  /// This is equivalent to `setToken`.
  @override
  Future<void> add(T data) async {
    await setToken(data);
  }

  /// Closes Fresh stream controllers.
  ///
  /// The [add],[setToken] and [removeToken] methods must not be called
  /// after this method.
  ///
  /// Calling this method more than once is allowed, but does nothing.
  @override
  Future<void> close() async {
    await _tokenController.close();
    await _controller.close();
  }
}
