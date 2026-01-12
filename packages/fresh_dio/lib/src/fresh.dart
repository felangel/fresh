import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';

/// Signature for `shouldRefresh` on [Fresh].
typedef ShouldRefresh = bool Function(Response<dynamic>? response);

/// Signature for `shouldRefreshBeforeRequest` on [Fresh].
typedef ShouldRefreshBeforeRequest<T> = bool Function(
  RequestOptions requestOptions,
  T? token,
);

/// Signature for `refreshToken` on [Fresh].
typedef RefreshToken<T> = Future<T> Function(T? token, Dio httpClient);

/// Signature for `isTokenRequired` on [Fresh].
typedef IsTokenRequired = bool Function(RequestOptions options);

/// {@template fresh}
/// A Dio Interceptor for automatic token refresh.
/// Requires a concrete implementation of [TokenStorage] and [RefreshToken].
/// Handles transparently refreshing/caching tokens.
///
/// By default, authentication headers are added to all requests.
/// Use the `isTokenRequired` parameter to conditionally skip authentication
/// for specific requests (e.g., login, registration, public endpoints).
///
/// ```dart
/// dio.interceptors.add(
///   Fresh<AuthToken>(
///     tokenStorage: InMemoryTokenStorage(),
///     refreshToken: (token, client) async {...},
///   ),
/// );
/// ```
/// {@endtemplate}
class Fresh<T> extends QueuedInterceptor with FreshMixin<T> {
  /// {@macro fresh}
  Fresh({
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T> refreshToken,
    required TokenHeaderBuilder<T> tokenHeader,
    ShouldRefresh? shouldRefresh,
    ShouldRefreshBeforeRequest<T>? shouldRefreshBeforeRequest,
    IsTokenRequired? isTokenRequired,
    Dio? httpClient,
  })  : _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _shouldRefreshBeforeRequest =
            shouldRefreshBeforeRequest ?? _defaultShouldRefreshBeforeRequest,
        _isTokenRequired = isTokenRequired,
        _httpClient = httpClient ?? Dio() {
    this.tokenStorage = tokenStorage;
  }

  /// A constructor that returns a [Fresh] interceptor that uses an
  /// [Token] token.
  ///
  /// By default, authentication headers are added to all requests.
  /// Use the `isTokenRequired` parameter to conditionally skip authentication:
  ///
  /// ```dart
  /// dio.interceptors.add(
  ///   Fresh.oAuth2(
  ///     tokenStorage: InMemoryTokenStorage<AuthToken>(),
  ///     refreshToken: (token, client) async {...},
  ///     // Optional: control which requests require authentication
  ///     isTokenRequired: (options) {
  ///       // Skip auth if explicitly disabled
  ///       if (options.extra['skipAuth'] == true) return false;
  ///
  ///       // Skip auth for login/register endpoints
  ///       if (options.path.contains('/auth/')) return false;
  ///
  ///       return true; // Add auth header to all other requests
  ///     },
  ///   ),
  /// );
  /// ```
  static Fresh<T> oAuth2<T extends Token>({
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T> refreshToken,
    Dio? httpClient,
    TokenHeaderBuilder<T>? tokenHeader,
    ShouldRefresh? shouldRefresh,
    ShouldRefreshBeforeRequest<T>? shouldRefreshBeforeRequest,
    IsTokenRequired? isTokenRequired,
  }) {
    return Fresh<T>(
      tokenStorage: tokenStorage,
      httpClient: httpClient,
      refreshToken: refreshToken,
      tokenHeader: tokenHeader ??
          (token) {
            return {
              'authorization': '${token.tokenType} ${token.accessToken}',
            };
          },
      shouldRefresh: shouldRefresh,
      shouldRefreshBeforeRequest: shouldRefreshBeforeRequest,
      isTokenRequired: isTokenRequired,
    );
  }

  final Dio _httpClient;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;
  final IsTokenRequired? _isTokenRequired;
  final ShouldRefreshBeforeRequest<T> _shouldRefreshBeforeRequest;
  final RefreshToken<T> _refreshToken;

  @override
  Future<dynamic> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    assert(
      _httpClient.interceptors.every((interceptor) => interceptor != this),
      '''
Cycle Detected!

The Fresh instance was created using an http client 
which already contains the Fresh instance as an interceptor.

This will cause an infinite loop on token refresh.
  
Example:

  ```
  final httpClient = Dio();
  final fresh = Fresh.oAuth2(
    httpClient: httpClient,
    ...
  );
  httpClient.interceptors.add(fresh); // <-- BAD
  ```
''',
    );

    // Check if token is required for this request
    if (_isTokenRequired != null && !_isTokenRequired!(options)) {
      // Mark request as not requiring auth to skip refresh attempts
      options.extra['_fresh_token_not_required'] = true;
      return handler.next(options);
    }

    var currentToken = await token;

    final shouldRefresh = _shouldRefreshBeforeRequest(
      options,
      currentToken,
    );

    if (shouldRefresh) {
      try {
        final refreshedToken = await _refreshToken(currentToken, _httpClient);
        await setToken(refreshedToken);
      } on RevokeTokenException catch (_) {
        await revokeToken();
      }

      currentToken = await token;
    }

    final headers = currentToken != null
        ? _tokenHeader(currentToken)
        : const <String, String>{};
    options.headers.addAll(headers);
    handler.next(options);
  }

  @override
  Future<dynamic> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    // Skip refresh if token was not required for this request
    final extra = response.requestOptions.extra;
    if (extra['_fresh_token_not_required'] == true) {
      return handler.next(response);
    }

    if (await token == null || !_shouldRefresh(response)) {
      return handler.next(response);
    }
    try {
      final refreshResponse = await _tryRefresh(response);
      handler.resolve(refreshResponse);
    } on DioException catch (error) {
      handler.reject(error);
    } catch (error, stackTrace) {
      response.extra.addAll({
        'fresh': {
          'message': 'refresh failure',
          'error': error,
          'stack_trace': stackTrace,
        },
      });
      handler.resolve(response);
    }
  }

  @override
  Future<dynamic> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // Skip refresh if token was not required for this request
    if (response?.requestOptions.extra['_fresh_token_not_required'] == true) {
      return handler.next(err);
    }

    if (response == null ||
        await token == null ||
        err.error is RevokeTokenException ||
        !_shouldRefresh(response)) {
      return handler.next(err);
    }
    try {
      final refreshResponse = await _tryRefresh(response);
      handler.resolve(refreshResponse);
    } on DioException catch (error) {
      handler.next(error);
    } catch (error, stackTrace) {
      response.extra.addAll({
        'fresh': {
          'message': 'refresh failure',
          'error': error,
          'stack_trace': stackTrace,
        },
      });
      handler.resolve(response);
    }
  }

  Future<Response<dynamic>> _tryRefresh(Response<dynamic> response) async {
    late final T refreshedToken;
    try {
      refreshedToken = await _refreshToken(await token, _httpClient);
    } on RevokeTokenException catch (error) {
      await clearToken();
      throw DioException(
        requestOptions: response.requestOptions,
        error: error,
        response: response,
      );
    }

    await setToken(refreshedToken);
    _httpClient.options.baseUrl = response.requestOptions.baseUrl;
    final data = response.requestOptions.data;
    return _httpClient.request<dynamic>(
      response.requestOptions.path,
      cancelToken: response.requestOptions.cancelToken,
      data: data is FormData ? data.clone() : data,
      onReceiveProgress: response.requestOptions.onReceiveProgress,
      onSendProgress: response.requestOptions.onSendProgress,
      queryParameters: response.requestOptions.queryParameters,
      options: Options(
        method: response.requestOptions.method,
        sendTimeout: response.requestOptions.sendTimeout,
        receiveTimeout: response.requestOptions.receiveTimeout,
        extra: response.requestOptions.extra,
        headers: response.requestOptions.headers
          ..addAll(_tokenHeader(refreshedToken)),
        responseType: response.requestOptions.responseType,
        contentType: response.requestOptions.contentType,
        validateStatus: response.requestOptions.validateStatus,
        receiveDataWhenStatusError:
            response.requestOptions.receiveDataWhenStatusError,
        followRedirects: response.requestOptions.followRedirects,
        maxRedirects: response.requestOptions.maxRedirects,
        requestEncoder: response.requestOptions.requestEncoder,
        responseDecoder: response.requestOptions.responseDecoder,
        listFormat: response.requestOptions.listFormat,
      ),
    );
  }

  static bool _defaultShouldRefresh(Response<dynamic>? response) {
    return response?.statusCode == 401;
  }

  static bool _defaultShouldRefreshBeforeRequest<T>(
    RequestOptions requestOptions,
    T? token,
  ) {
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
