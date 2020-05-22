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

/// Function responsible for building the token header(s) give a [token].
typedef TokenHeaderBuilder<T extends Token> = Map<String, String> Function(
  T token,
);

/// A [TokenStorage] implementation that keeps the token in memory.
class InMemoryTokenStorage<T extends Token> implements TokenStorage<T> {
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
