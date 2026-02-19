/// {@template token}
/// Base class for all authentication tokens.
/// {@endtemplate}
abstract class Token {
  /// {macro token}
  const Token({
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

  /// The date the token will expire.
  DateTime? get expiresAt;
}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// with added support for the issue date.
/// {@endtemplate}
class OAuth2Token extends Token {
  /// {macro oauth2_token}
  const OAuth2Token({
    required String accessToken,
    String? refreshToken,
    String? tokenType,
    this.expiresIn,
    this.scope,
    this.issuedAt,
  }) : super(
          accessToken: accessToken,
          refreshToken: refreshToken,
          tokenType: tokenType ?? 'bearer',
        );

  /// If the access token expires, the server should reply
  /// with the duration of time the access token is granted for.
  /// In seconds.
  final int? expiresIn;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String? scope;

  /// The date the token was issued.
  final DateTime? issuedAt;

  /// The date the token will expire.
  @override
  DateTime? get expiresAt {
    final expiresIn = this.expiresIn;
    final issuedAt = this.issuedAt;
    if (expiresIn == null || issuedAt == null) return null;

    return issuedAt.add(Duration(seconds: expiresIn));
  }

  @override
  String toString() {
    final fields = <String>[];

    // ignore: cascade_invocations
    fields.add('accessToken: ${_maskToken(accessToken)}');

    if (refreshToken != null) {
      fields.add('refreshToken: ${_maskToken(refreshToken!)}');
    }

    if (tokenType != null) {
      fields.add('tokenType: $tokenType');
    }

    if (expiresIn != null) {
      fields.add('expiresIn: $expiresIn');
    }

    if (scope != null) {
      fields.add('scope: $scope');
    }

    if (issuedAt != null) {
      fields.add('issuedAt: $issuedAt');
    }

    if (expiresAt != null) {
      fields.add('expiresAt: $expiresAt');
    }

    return 'OAuth2Token{${fields.join(', ')}}';
  }

  String _maskToken(String token) {
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }
}
