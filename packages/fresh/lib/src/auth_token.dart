/// {@template auth_token}
/// Base class for all authentication tokens.
/// {@endtemplate}
class AuthToken {
  /// {macro auth_token}
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'bearer',
  });

  /// The access token string as issued by the authorization server.
  final String accessToken;

  /// Token which applications can use to obtain another access token.
  final String? refreshToken;

  /// The type of token this is, typically just the string “bearer”.
  final String? tokenType;
}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// {@endtemplate}
class OAuth2Token extends AuthToken {
  /// {macro oauth2_token}
  const OAuth2Token({
    required super.accessToken,
    super.refreshToken,
    super.tokenType,
    this.expiresIn,
    this.scope,
  });

  /// If the access token expires, the server should reply
  /// with the duration of time the access token is granted for.
  /// In seconds.
  final int? expiresIn;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String? scope;
}

/// {@template fresh_token}
/// Extended version of [OAuth2Token] with support for validation.
/// {@endtemplate}
class FreshAuthToken extends AuthToken {
  /// {macro fresh_token}
  const FreshAuthToken({
    required super.accessToken,
    super.refreshToken,
    super.tokenType,
    this.expireTime,
    this.issuedAt,
    this.userId,
    this.scope,
  });

  /// The date the token will expire.
  DateTime? get expireDate => issuedAt?.add(expireTime ?? Duration.zero);

  /// The duration of the token's validity.
  final Duration? expireTime;

  /// The date the token was issued.
  final DateTime? issuedAt;

  /// The user id, this is used to identify the user in the system.
  final Object? userId;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String? scope;
}
