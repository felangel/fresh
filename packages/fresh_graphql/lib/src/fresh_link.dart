import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;

/// Signature for `shouldRefresh` on [FreshLink].
typedef ShouldRefresh = bool Function(Request);

/// Signature for `refreshToken` on [FreshLink].
typedef RefreshToken<T> = Future<T> Function(T, http.Client);

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
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T?> refreshToken,
    required ShouldRefresh shouldRefresh,
    TokenHeaderBuilder<T?>? tokenHeader,
  })  : _refreshToken = refreshToken,
        _tokenHeader = (tokenHeader ?? (_) => <String, String>{}),
        _shouldRefresh = shouldRefresh {
    this.tokenStorage = tokenStorage;
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
    required TokenStorage<OAuth2Token> tokenStorage,
    required RefreshToken<OAuth2Token?> refreshToken,
    required ShouldRefresh shouldRefresh,
    TokenHeaderBuilder<OAuth2Token?>? tokenHeader,
  }) {
    return FreshLink<OAuth2Token>(
      refreshToken: refreshToken,
      tokenStorage: tokenStorage,
      shouldRefresh: shouldRefresh,
      tokenHeader: tokenHeader ??
          (token) {
            return {
              'authorization': '${token?.tokenType} ${token?.accessToken}',
            };
          },
    );
  }

  final RefreshToken<T?> _refreshToken;
  final TokenHeaderBuilder<T?> _tokenHeader;
  final ShouldRefresh _shouldRefresh;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    // fresh_graphql should not be used as the last link
    if (forward == null) return;

    final currentToken = await token;
    if (currentToken == null) {
      yield* forward(request);
      return;
    }

    final T? activeToken;
    if (_shouldRefresh(request)) {
      try {
        activeToken = await _refreshToken(currentToken, http.Client());
        await setToken(activeToken);
      } on RevokeTokenException catch (_) {
        unawaited(revokeToken());
        yield* forward(request);
        return;
      }
    } else {
      activeToken = currentToken;
    }

    final tokenHeaders = _tokenHeader(activeToken);
    final updatedRequest = request.updateContextEntry<HttpLinkHeaders>(
      (headers) => HttpLinkHeaders(
        headers: {
          ...headers?.headers ?? <String, String>{},
        }..addAll(tokenHeaders),
      ),
    );

    yield* forward(updatedRequest);
  }
}
