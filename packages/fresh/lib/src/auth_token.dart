/// {@template auth_token}
/// Base class for all authentication tokens.
/// {@endtemplate}
abstract class AuthToken {
  /// {macro auth_token}
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'bearer',
    this.issuedAt,
  });

  /// The date the token will expire.
  DateTime? get expireDate => null;

  /// The access token string as issued by the authorization server.
  final String accessToken;

  /// Token which applications can use to obtain another access token.
  final String? refreshToken;

  /// The type of token this is, typically just the string “bearer”.
  final String? tokenType;

  /// The date the token was issued.
  final DateTime? issuedAt;

  /// Creates a copy of the token with the given properties updated.
  AuthToken copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    DateTime? issuedAt,
  });
}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// with added support for the issue date.
/// {@endtemplate}
interface class OAuth2Token extends AuthToken {
  /// {macro oauth2_token}
  const OAuth2Token({
    required super.accessToken,
    super.refreshToken,
    super.tokenType,
    super.issuedAt,
    this.expiresIn,
    this.scope,
  });

  /// The date the token will expire.
  @override
  DateTime? get expireDate => issuedAt?.add(Duration(seconds: expiresIn ?? 0));

  /// If the access token expires, the server should reply
  /// with the duration of time the access token is granted for.
  /// In seconds.
  final int? expiresIn;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String? scope;

  /// Creates a copy of the token with the given properties updated.
  @override
  OAuth2Token copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    DateTime? issuedAt,
    int? expiresIn,
    String? scope,
  }) =>
      OAuth2Token(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        tokenType: tokenType ?? this.tokenType,
        issuedAt: issuedAt ?? this.issuedAt,
        expiresIn: expiresIn ?? this.expiresIn,
        scope: scope ?? this.scope,
      );
}
