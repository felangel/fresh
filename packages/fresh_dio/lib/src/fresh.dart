import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_dio/fresh_dio.dart';

/// Signature for `shouldRefresh` on [Fresh].
typedef ShouldRefresh = bool Function(Response? response);

/// Signature for `refreshToken` on [Fresh].
typedef RefreshToken<T> = Future<T> Function(T? token, Dio httpClient);

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
    required TokenHeaderBuilder<T> tokenHeader,
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T> refreshToken,
    ShouldRefresh? shouldRefresh,
    Dio? httpClient,
  })  : _refreshToken = refreshToken,
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
    required TokenStorage<OAuth2Token> tokenStorage,
    required RefreshToken<OAuth2Token> refreshToken,
    ShouldRefresh? shouldRefresh,
    TokenHeaderBuilder<OAuth2Token>? tokenHeader,
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
    final headers = currentToken != null
        ? _tokenHeader(currentToken)
        : const <String, String>{};
    options.headers.addAll(headers);
    return options;
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (await token == null || !_shouldRefresh(response)) {
      return response;
    }
    return _tryRefresh(response);
  }

  @override
  Future<dynamic> onError(DioError err) async {
    final response = err.response;
    if (await token == null ||
        err.error is RevokeTokenException ||
        !_shouldRefresh(response)) {
      return err;
    }
    return _tryRefresh(response);
  }

  Future<dynamic> _tryRefresh(Response? response) async {
    T refreshedToken;
    try {
      refreshedToken = await _refreshToken(await token, _httpClient);
    } on RevokeTokenException catch (error) {
      await clearToken();
      return DioError(
        error: error,
        request: response?.request,
        response: response,
      );
    }

    await setToken(refreshedToken);
    if (response != null) {
      _httpClient..options.baseUrl = response.request.baseUrl;
      return await _httpClient.request<dynamic>(
        response.request.path,
        cancelToken: response.request.cancelToken,
        data: response.request.data,
        onReceiveProgress: response.request.onReceiveProgress,
        onSendProgress: response.request.onSendProgress,
        queryParameters: response.request.queryParameters,
        options: Options(
          method: response.request.method,
          sendTimeout: response.request.sendTimeout,
          receiveTimeout: response.request.receiveTimeout,
          extra: response.request.extra,
          headers: response.request.headers,
          responseType: response.request.responseType,
          contentType: response.request.contentType,
          validateStatus: response.request.validateStatus,
          receiveDataWhenStatusError:
              response.request.receiveDataWhenStatusError,
          followRedirects: response.request.followRedirects,
          maxRedirects: response.request.maxRedirects,
          requestEncoder: response.request.requestEncoder,
          responseDecoder: response.request.responseDecoder,
          listFormat: response.request.listFormat,
        ),
      );
    }
  }

  static bool _defaultShouldRefresh(Response? response) {
    return response?.statusCode == 401;
  }
}
