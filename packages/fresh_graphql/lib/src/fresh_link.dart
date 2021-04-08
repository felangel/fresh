import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;
import 'package:pedantic/pedantic.dart';

typedef ShouldRefresh = bool Function(Response);

typedef RefreshToken<T> = Future<T?> Function(T?, http.Client);

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
        _tokenHeader = tokenHeader,
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
  final TokenHeaderBuilder<T?>? _tokenHeader;
  final ShouldRefresh _shouldRefresh;

  @override
  Stream<Response> request(
    Request request, [
    NextLink? forward,
  ]) async* {
    final currentToken = await token;
    final tokenHeaders = currentToken != null && _tokenHeader != null
        ? _tokenHeader!(currentToken)
        : const <String, String>{};

    request.updateContextEntry<HttpLinkHeaders>(
      (headers) => HttpLinkHeaders(
        headers: {
          ...headers?.headers ?? <String, String>{},
        }..addAll(tokenHeaders),
      ),
    );

    if (forward != null) {
      await for (final result in forward(request)) {
        final nextToken = await token;
        if (nextToken != null && _shouldRefresh(result)) {
          try {
            final refreshedToken = await _refreshToken(
              nextToken,
              http.Client(),
            );
            await setToken(refreshedToken);
            final tokenHeaders = _tokenHeader!(refreshedToken);
            request.updateContextEntry<HttpLinkHeaders>(
              (headers) => HttpLinkHeaders(
                headers: {
                  ...headers?.headers ?? <String, String>{},
                }..addAll(tokenHeaders),
              ),
            );
            yield* forward(request);
          } on RevokeTokenException catch (_) {
            unawaited(revokeToken());
            yield result;
          }
        } else {
          yield result;
        }
      }
    }
  }
}
