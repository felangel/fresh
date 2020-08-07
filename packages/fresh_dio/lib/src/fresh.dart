import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:meta/meta.dart';

typedef ShouldRefresh = bool Function(Response response);

typedef RefreshToken<T> = Future<T> Function(T token, Dio httpClient);

/// {@template fresh}
/// A Dio Interceptor for automatic token refresh.
/// Requires a concrete implementation of [TokenStorage] and [RefreshToken].
/// Handles transparently refreshing/caching tokens.
///
/// ```dart
/// dio.interceptors.add(
///   Fresh<OAuth2Token>(
///     tokenStorage: InMemoryTokenStorage(),
///     refreshToken: (token, client) async {...},
///   ),
/// );
/// ```
/// {@endtemplate}
class Fresh<T> extends Interceptor with FreshMixin<T> {
  /// {@macro fresh}
  Fresh({
    @required TokenHeaderBuilder<T> tokenHeader,
    @required TokenStorage<T> tokenStorage,
    @required RefreshToken<T> refreshToken,
    ShouldRefresh shouldRefresh,
    Dio httpClient,
  })  : assert(tokenStorage != null),
        assert(refreshToken != null),
        assert(tokenHeader != null),
        _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _httpClient = httpClient ?? Dio() {
    this.tokenStorage = tokenStorage;
  }

  /// A constructor that returns a [Fresh] interceptor that uses an
  /// [OAuth2Token] token.
  ///
  /// ```dart
  /// dio.interceptors.add(
  ///   Fresh.oAuth2(
  ///     tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
  ///     refreshToken: (token, client) async {...},
  ///   ),
  /// );
  /// ```
  static Fresh<OAuth2Token> oAuth2({
    @required TokenStorage<OAuth2Token> tokenStorage,
    @required RefreshToken<OAuth2Token> refreshToken,
    ShouldRefresh shouldRefresh,
    TokenHeaderBuilder<OAuth2Token> tokenHeader,
  }) {
    return Fresh<OAuth2Token>(
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

  final Dio _httpClient;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;
  final RefreshToken<T> _refreshToken;

  @override
  Future<dynamic> onRequest(RequestOptions options) async {
    final currentToken = await token;
    final tokenHeader = _tokenHeader(currentToken);

    if (currentToken != null) {
      (options.headers ?? <String, String>{}).addAll(tokenHeader);
    }
    return options;
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (token == null || !_shouldRefresh(response)) {
      return response;
    }
    return _tryRefresh(response);
  }

  @override
  Future<dynamic> onError(DioError err) async {
    final response = err.response;
    if (token == null || !_shouldRefresh(response)) {
      return err;
    }
    return _tryRefresh(response);
  }

  Future<Response> _tryRefresh(Response response) async {
    T refreshedToken;
    try {
      refreshedToken = await _refreshToken(await token, _httpClient);
    } on RevokeTokenException catch (_) {
      await clearToken();
      return response;
    }

    await setToken(refreshedToken);

    return await _httpClient.request(
      response.request.path,
      cancelToken: response.request.cancelToken,
      data: response.request.data,
      onReceiveProgress: response.request.onReceiveProgress,
      onSendProgress: response.request.onSendProgress,
      queryParameters: response.request.queryParameters,
      options: response.request..headers.addAll(_tokenHeader(await token)),
    );
  }

  static bool _defaultShouldRefresh(Response response) {
    return response?.statusCode == 401;
  }
}
