import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;

/// Signature for `shouldRefresh` on [FreshLink].
typedef ShouldRefresh = bool Function(Response);

/// Signature for `shouldRefreshBeforeRequest` on [FreshLink].
typedef ShouldRefreshBeforeRequest<T> = bool Function(
  Request request,
  T? token,
);

/// Signature for `refreshToken` on [FreshLink].
typedef RefreshToken<T> = Future<T> Function(T, http.Client);

/// {@template fresh_link}
/// A GraphQL Link which handles manages an authentication token automatically.
///
/// A constructor that returns a Fresh interceptor that uses the
/// [Token] token, the standard token class and define the`
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
    ShouldRefreshBeforeRequest<T?>? shouldRefreshBeforeRequest,
    TokenHeaderBuilder<T?>? tokenHeader,
  })  : _refreshToken = refreshToken,
        _tokenHeader = (tokenHeader ?? (_) => <String, String>{}),
        _shouldRefresh = shouldRefresh,
        _shouldRefreshBeforeRequest =
            shouldRefreshBeforeRequest ?? _defaultShouldRefreshBeforeRequest {
    this.tokenStorage = tokenStorage;
  }

  ///{@template fresh_link}
  ///A GraphQL Link which handles manages an authentication token automatically.
  ///
  /// ```dart
  /// final freshLink = FreshLink.oAuth2(
  ///   tokenStorage: InMemoryTokenStorage<AuthToken>(),
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
  static FreshLink<T> oAuth2<T extends Token>({
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T?> refreshToken,
    required ShouldRefresh shouldRefresh,
    ShouldRefreshBeforeRequest<T>? shouldRefreshBeforeRequest,
    TokenHeaderBuilder<T?>? tokenHeader,
  }) {
    return FreshLink<T>(
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
  final ShouldRefreshBeforeRequest<T?> _shouldRefreshBeforeRequest;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final httpClient = http.Client();

    var currentToken = await token;

    final shouldRefresh = _shouldRefreshBeforeRequest.call(
      request,
      currentToken,
    );

    if (shouldRefresh) {
      try {
        final refreshedToken = await _refreshToken(currentToken, httpClient);
        await setToken(refreshedToken);
      } on RevokeTokenException catch (_) {
        await revokeToken();
      }

      currentToken = await token;
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
              httpClient,
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
            // ignore: unawaited_futures
            revokeToken();
            yield result;
          }
        } else {
          yield result;
        }
      }
    }
  }

  static bool _defaultShouldRefreshBeforeRequest<T>(Request request, T? token) {
    if (token is Token) {
      final expiresAt = token.expiresAt;
      if (expiresAt != null) {
        final now = DateTime.now();
        return expiresAt.isBefore(now);
      }
    }

    return false;
  }
}
