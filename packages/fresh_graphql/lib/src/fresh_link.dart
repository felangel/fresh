import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;

/// Signature for `shouldRefresh` on [FreshLink].
typedef ShouldRefresh = bool Function(Response);

/// Signature for proactive token validation before a request.
typedef ShouldRefreshBeforeRequest<T> = Future<bool> Function(T? token);

/// Signature for `refreshToken` on [FreshLink].
typedef RefreshToken<T> = Future<T> Function(T, http.Client);

/// {@template fresh_link}
/// A GraphQL Link which manages an authentication token automatically.
///
/// A constructor that returns a Fresh interceptor that uses the
/// [OAuth2Token] token, the standard token class and defines the
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
    ShouldRefreshBeforeRequest<T>? shouldRefreshBeforeRequest,
    TokenHeaderBuilder<T?>? tokenHeader,
  })  : _refreshToken = refreshToken,
        _tokenHeader = (tokenHeader ?? (_) => <String, String>{}),
        _shouldRefresh = shouldRefresh,
        _shouldRefreshBeforeRequest = shouldRefreshBeforeRequest {
    this.tokenStorage = tokenStorage;
  }

  ///{@template fresh_link}
  ///A GraphQL Link which manages an authentication token automatically.
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
    ShouldRefreshBeforeRequest<OAuth2Token>? shouldRefreshBeforeRequest,
    TokenHeaderBuilder<OAuth2Token?>? tokenHeader,
  }) {
    return FreshLink<OAuth2Token>(
      refreshToken: refreshToken,
      tokenStorage: tokenStorage,
      shouldRefresh: shouldRefresh,
      shouldRefreshBeforeRequest: shouldRefreshBeforeRequest,
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
  final ShouldRefreshBeforeRequest<T>? _shouldRefreshBeforeRequest;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    var currentToken = await token;

    if (_shouldRefreshBeforeRequest != null &&
        currentToken != null &&
        await _shouldRefreshBeforeRequest!(currentToken)) {
      try {
        final refreshedToken = await _refreshToken(currentToken, http.Client());
        await setToken(refreshedToken);
        currentToken = await token;
      } on RevokeTokenException catch (_) {
        unawaited(revokeToken());
      }
    }

    final tokenHeaders = currentToken != null
        ? _tokenHeader(currentToken)
        : const <String, String>{};

    final updatedRequest = request.updateContextEntry<HttpLinkHeaders>(
      (headers) => HttpLinkHeaders(
        headers: {
          ...headers?.headers ?? <String, String>{},
        }..addAll(tokenHeaders),
      ),
    );

    if (forward != null) {
      await for (final result in forward(updatedRequest)) {
        final nextToken = await token;
        if (nextToken != null && _shouldRefresh(result)) {
          try {
            final refreshedToken = await _refreshToken(
              nextToken,
              http.Client(),
            );
            await setToken(refreshedToken);
            final tokenHeaders = _tokenHeader(refreshedToken);
            yield* forward(
              request.updateContextEntry<HttpLinkHeaders>(
                (headers) => HttpLinkHeaders(
                  headers: {
                    ...headers?.headers ?? <String, String>{},
                  }..addAll(tokenHeaders),
                ),
              ),
            );
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
