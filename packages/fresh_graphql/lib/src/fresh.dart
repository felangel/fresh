import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:graphql/client.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';

typedef ShouldRefresh = bool Function(FetchResult result);

typedef RefreshToken<T> = Future<T> Function(T token, Client httpClient);

/// {@template fresh_link}
/// A GraphQL Link which handles manages an authentication token automatically.
/// {@endtemplate}
class FreshLink<T extends Token> extends Link {
  /// {@macro fresh_link}
  FreshLink({
    @required TokenStorage tokenStorage,
    @required RefreshToken<T> refreshToken,
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
              if (shouldRefresh(result)) {
                try {
                  final refreshedToken = await refreshToken(token, Client());
                  await tokenStorage.write(refreshedToken);
                  _authenticationStatus = AuthenticationStatus.authenticated;
                  _controller.add(_authenticationStatus);
                  final headers = await tokenHeader(refreshedToken);
                  operation.setContext(
                    <String, Map<String, String>>{'headers': headers},
                  );
                  yield* forward(operation);
                } on RevokeTokenException catch (_) {
                  await tokenStorage.delete();
                  _authenticationStatus = AuthenticationStatus.unauthenticated;
                  _controller.add(AuthenticationStatus.unauthenticated);
                  yield result;
                }
              } else {
                yield result;
              }
            }
          },
        ) {
    tokenStorage.read().then((token) {
      _authenticationStatus = token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    });
  }

  static final StreamController _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  static AuthenticationStatus _authenticationStatus =
      AuthenticationStatus.initial;

  final TokenStorage<T> _tokenStorage;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  /// If the provided token is null, the `AuthenticationStatus` will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  ///
  /// This method should be called after making a successful token request.
  Future<void> setToken(Token token) async {
    await _tokenStorage.write(token);
    final authenticationStatus = token == null
        ? AuthenticationStatus.unauthenticated
        : AuthenticationStatus.authenticated;
    _authenticationStatus = authenticationStatus;
    _controller.add(authenticationStatus);
  }

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
