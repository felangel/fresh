import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';

typedef ShouldRefresh = bool Function(FetchResult);

typedef RefreshToken<T> = Future<T> Function(T, Client);

/// {@template fresh_link}
/// A GraphQL Link which handles manages an authentication token automatically.
///
/// A constructor that returns a Fresh interceptor that uses the
/// `OAuth2Token` token, the standard token class and define the`
/// tokenHeader as 'authorization': '${token.tokenType} ${token.accessToken}'
///
/// ```dart
/// final freshLink = FreshLink(
///   tokenStorage: InMemoryTokenStorage(),
///   refreshToken: (token, client) {
///     // Perform refresh and return new token
///   },
/// );
/// final graphQLClient = GraphQLClient(
///   cache: InMemoryCache(),
///   link: Link.from([freshLink, HttpLink(uri: 'https://my.graphql.api')]),
/// );
/// ```
/// {@endtemplate}
class FreshLink<T> extends Link implements FreshBase<T> {
  /// {@macro fresh_link}

  FreshLink({
    TokenStorage<T> tokenStorage,
    RefreshToken<T> refreshToken,
    TokenHeaderBuilder<T> tokenHeader,
    ShouldRefresh shouldRefresh,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _freshController = FreshController<T>(tokenStorage: tokenStorage),
        _tokenStorage = tokenStorage,
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh {
    request = _buildRequest;
  }

  ///{@template fresh_link}
  ///A GraphQL Link which handles manages an authentication token automatically.
  ///
  /// ```dart
  /// final freshLink = FreshLink.oAuth2Token(
  ///   tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
  ///   refreshToken: (token, client) {
  ///     // Perform refresh and return new token
  ///   },
  /// );
  /// final graphQLClient = GraphQLClient(
  ///   cache: InMemoryCache(),
  ///   link: Link.from([freshLink, HttpLink(uri: 'https://my.graphql.api')]),
  /// );
  /// ```
  /// {@endtemplate}
  static FreshLink<OAuth2Token> oAuth2Token({
    @required TokenStorage<OAuth2Token> tokenStorage,
    @required RefreshToken<OAuth2Token> refreshToken,
    ShouldRefresh shouldRefresh,
    TokenHeaderBuilder<OAuth2Token> tokenHeader,
  }) {
    return FreshLink<OAuth2Token>(
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

  final TokenStorage<T> _tokenStorage;
  final RefreshToken<T> _refreshToken;
  final FreshController<T> _freshController;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;

  Stream<FetchResult> _buildRequest(Operation operation,
      [Stream<FetchResult> forward(Operation op)]) async* {
    final token = await _getToken();
    final headers =
        token != null ? await _tokenHeader(token) : const <String, String>{};

    operation.setContext(
      <String, Map<String, String>>{'headers': headers},
    );

    await for (final result in forward(operation)) {
      if (token != null && _shouldRefresh(result)) {
        try {
          final refreshedToken = await _refreshToken(token, Client());
          await _tokenStorage.write(refreshedToken);
          final headers = await _tokenHeader(refreshedToken);
          operation.setContext(
            <String, Map<String, String>>{'headers': headers},
          );
          yield* forward(operation);
        } on RevokeTokenException catch (_) {
          _freshController.revokeToken();
          yield result;
        }
      } else {
        yield result;
      }
    }
  }

  Stream<AuthenticationStatus> get authenticationStatus =>
      _freshController.authenticationStatus;

  @override
  Stream<T> get currentToken => _freshController.currentToken;

  Future<void> setToken(T token) async {
    await _freshController.setToken(token);
  }

  Future<void> removeToken() => _freshController.removeToken();

  static bool _defaultShouldRefresh(FetchResult result) {
    return result?.statusCode == 401;
  }

  Future<T> _getToken() async {
    if (_freshController.authenticationStatusValue !=
        AuthenticationStatus.initial) return _freshController.token;
    final token = await _tokenStorage.read();
    _freshController.updateStatus(token);
    return token;
  }
}
