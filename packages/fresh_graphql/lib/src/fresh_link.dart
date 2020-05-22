import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';

typedef ShouldRefresh = bool Function(FetchResult);

typedef RefreshToken<T> = Future<T> Function(T, Client);

typedef OnRefreshFailure = void Function();

/// {@template fresh_link}
/// A GraphQL Link which handles manages an authentication token automatically.
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
class FreshLink<T extends Token> extends Link {
  /// {@macro fresh_link}
  FreshLink({
    @required TokenStorage<T> tokenStorage,
    @required RefreshToken<T> refreshToken,
    OnRefreshFailure onRefreshFailure,
    TokenHeaderBuilder<T> tokenHeader = _defaultTokenHeader,
    ShouldRefresh shouldRefresh = _defaultShouldRefresh,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _tokenStorage = tokenStorage,
        super(
          request: (operation, [forward]) async* {
            final token = await tokenStorage.read();
            final headers = token != null
                ? await tokenHeader(token)
                : const <String, String>{};

            operation.setContext(
              <String, Map<String, String>>{'headers': headers},
            );

            await for (final result in forward(operation)) {
              if (token != null && shouldRefresh(result)) {
                try {
                  final refreshedToken = await refreshToken(token, Client());
                  await tokenStorage.write(refreshedToken);
                  final headers = await tokenHeader(refreshedToken);
                  operation.setContext(
                    <String, Map<String, String>>{'headers': headers},
                  );
                  yield* forward(operation);
                } on RevokeTokenException catch (_) {
                  await tokenStorage.delete();
                  onRefreshFailure?.call();
                  yield result;
                }
              } else {
                yield result;
              }
            }
          },
        );

  final TokenStorage<T> _tokenStorage;

  /// Sets the internal [token] to the provided [token].
  /// This method should be called after making a successful token request.
  Future<void> setToken(Token token) => _tokenStorage.write(token);

  static bool _defaultShouldRefresh(FetchResult result) {
    return result?.statusCode == 401;
  }

  static Map<String, String> _defaultTokenHeader(Token token) {
    if (token is OAuth2Token) {
      return {
        'authorization': '${token.tokenType} ${token.accessToken}',
      };
    }
    throw UnimplementedError();
  }
}
