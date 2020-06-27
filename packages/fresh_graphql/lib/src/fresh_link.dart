import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';

typedef ShouldRefresh = bool Function(FetchResult);

typedef RefreshToken<T> = Future<T> Function(T, Client);

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
class FreshLink<T> {
  /// {@macro fresh_link}

  TokenStorage<T> tokenStorage;
  RefreshToken<T> refreshToken;
  TokenHeaderBuilder<T> tokenHeader;
  ShouldRefresh shouldRefresh;

  FreshLink({
    @required this.tokenStorage,
    @required this.refreshToken,
    @required this.tokenHeader,
    this.shouldRefresh = _defaultShouldRefresh,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        _tokenStorage = tokenStorage {
    unawaited(_getToken(tokenStorage));
  }

  static FreshLink<OAuth2Token> auth2Token({
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

  Link get link => Link(request: _buildRequest);

  Stream<FetchResult> _buildRequest(Operation operation,
      [Stream<FetchResult> forward(Operation op)]) async* {
    final token = await _getToken(tokenStorage);
    final headers =
        token != null ? await tokenHeader(token) : const <String, String>{};

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
          if (_authenticationStatus != AuthenticationStatus.unauthenticated) {
            _authenticationStatus = AuthenticationStatus.unauthenticated;
            _controller.add(AuthenticationStatus.unauthenticated);
          }
          yield result;
        }
      } else {
        yield result;
      }
    }
  }

  static var _controller = StreamController<AuthenticationStatus>();
  static var _authenticationStatus = AuthenticationStatus.initial;
  T _token;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  final TokenStorage<T> _tokenStorage;

  /// Sets the internal [token] to the provided [token].
  /// This method should be called after making a successful token request.
  Future<void> setToken(T token) async {
    token == null
        ? await _tokenStorage.delete()
        : await _tokenStorage.write(token);
    final authenticationStatus = token == null
        ? AuthenticationStatus.unauthenticated
        : AuthenticationStatus.authenticated;
    if (_authenticationStatus != authenticationStatus) {
      _authenticationStatus = authenticationStatus;
      _controller.add(authenticationStatus);
    }
    _token = token;
  }

  static bool _defaultShouldRefresh(FetchResult result) {
    return result?.statusCode == 401;
  }

  Future<T> _getToken(
    TokenStorage<T> tokenStorage,
  ) async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    final token = await tokenStorage.read();
    final authenticationStatus = token != null
        ? AuthenticationStatus.authenticated
        : AuthenticationStatus.unauthenticated;
    if (_authenticationStatus != authenticationStatus) {
      _authenticationStatus = authenticationStatus;
      _controller.add(authenticationStatus);
    }
    _token = token;
    return _token;
  }

  /// Internal API to reset the state of the [FreshLink].
  /// This should only be used for testing purposes.
  @visibleForTesting
  void reset() {
    _authenticationStatus = AuthenticationStatus.initial;
    _token = null;
    _controller?.close();
    _controller = StreamController<AuthenticationStatus>();
  }
}
