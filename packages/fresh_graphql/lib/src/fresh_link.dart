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
/// [OAuth2Token] token, the standard token class and define the`
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
class FreshLink<T> extends Link with FreshMixin<T> {
  /// {@macro fresh_link}
  FreshLink({
    TokenStorage<T> tokenStorage,
    RefreshToken<T> refreshToken,
    TokenHeaderBuilder<T> tokenHeader,
    ShouldRefresh shouldRefresh,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh {
    this.tokenStorage = tokenStorage;
    request = _buildRequest;
  }

  ///{@template fresh_link}
  ///A GraphQL Link which handles manages an authentication token automatically.
  ///
  /// ```dart
  /// final freshLink = FreshLink.oAuth2(
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
  static FreshLink<OAuth2Token> oAuth2({
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
          },
    );
  }

  final RefreshToken<T> _refreshToken;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;

  Stream<FetchResult> _buildRequest(Operation operation,
      [Stream<FetchResult> forward(Operation op)]) async* {
    final currentToken = await token;
    final headers = currentToken != null && _tokenHeader != null
        ? await _tokenHeader(currentToken)
        : const <String, String>{};

    operation.setContext(
      <String, Map<String, String>>{'headers': headers},
    );

    await for (final result in forward(operation)) {
      if (token != null && _shouldRefresh(result)) {
        try {
          final refreshedToken = await _refreshToken(await token, Client());
          await setToken(refreshedToken);
          final headers = await _tokenHeader(refreshedToken);
          operation.setContext(
            <String, Map<String, String>>{'headers': headers},
          );
          yield* forward(operation);
        } on RevokeTokenException catch (_) {
          revokeToken();
          yield result;
        }
      } else {
        yield result;
      }
    }
  }

  static bool _defaultShouldRefresh(FetchResult result) {
    return result?.statusCode == 401;
  }
}
