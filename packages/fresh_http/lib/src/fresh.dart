import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:http/http.dart' as http;

/// Signature for `shouldRefresh` on [Fresh].
typedef ShouldRefresh = bool Function(http.Response? response);

/// Signature for `shouldRefreshBeforeRequest` on [Fresh].
typedef ShouldRefreshBeforeRequest<T> = bool Function(
  http.BaseRequest request,
  T? token,
);

/// Signature for `refreshToken` on [Fresh].
typedef RefreshToken<T> = Future<T> Function(T? token, http.Client httpClient);

/// Signature for `isTokenRequired` on [Fresh].
typedef IsTokenRequired = bool Function(http.BaseRequest request);

/// {@template fresh}
/// An [http.BaseClient] that transparently refreshes tokens.
/// Requires a concrete implementation of [TokenStorage] and [RefreshToken].
///
/// By default, authentication headers are added to all requests.
/// Use the `isTokenRequired` parameter to conditionally skip authentication
/// for specific requests (e.g., login, registration, public endpoints).
///
/// ```dart
/// final client = Fresh<AuthToken>(
///   tokenStorage: InMemoryTokenStorage(),
///   refreshToken: (token, client) async {...},
///   tokenHeader: (token) => {'authorization': 'Bearer ${token.accessToken}'},
/// );
/// ```
/// {@endtemplate}
class Fresh<T> extends http.BaseClient with FreshMixin<T> {
  /// {@macro fresh}
  Fresh({
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T> refreshToken,
    required TokenHeaderBuilder<T> tokenHeader,
    ShouldRefresh? shouldRefresh,
    ShouldRefreshBeforeRequest<T>? shouldRefreshBeforeRequest,
    IsTokenRequired? isTokenRequired,
    http.Client? httpClient,
  })  : _refreshToken = refreshToken,
        _tokenHeader = tokenHeader,
        _shouldRefresh = shouldRefresh ?? _defaultShouldRefresh,
        _shouldRefreshBeforeRequest =
            shouldRefreshBeforeRequest ?? _defaultShouldRefreshBeforeRequest,
        _isTokenRequired = isTokenRequired,
        _httpClient = httpClient ?? http.Client() {
    this.tokenStorage = tokenStorage;
  }

  /// A constructor that returns a [Fresh] client that uses an OAuth2 [Token].
  ///
  /// By default, authentication headers are added to all requests.
  /// Use the `isTokenRequired` parameter to conditionally skip authentication:
  ///
  /// ```dart
  /// final client = Fresh.oAuth2(
  ///   tokenStorage: InMemoryTokenStorage<AuthToken>(),
  ///   refreshToken: (token, client) async {...},
  ///   // Optional: control which requests require authentication
  ///   isTokenRequired: (request) {
  ///     if (request.url.path.contains('/auth/')) return false;
  ///     return true;
  ///   },
  /// );
  /// ```
  static Fresh<T> oAuth2<T extends Token>({
    required TokenStorage<T> tokenStorage,
    required RefreshToken<T> refreshToken,
    http.Client? httpClient,
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

  final http.Client _httpClient;
  final TokenHeaderBuilder<T> _tokenHeader;
  final ShouldRefresh _shouldRefresh;
  final ShouldRefreshBeforeRequest<T> _shouldRefreshBeforeRequest;
  final IsTokenRequired? _isTokenRequired;
  final RefreshToken<T> _refreshToken;

  @override
  Future<T> performTokenRefresh(T? token) => _refreshToken(token, _httpClient);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Check if token is required for this request.
    if (_isTokenRequired != null && !_isTokenRequired!(request)) {
      return _httpClient.send(request);
    }

    var currentToken = await token;
    final shouldRefresh = _shouldRefreshBeforeRequest(request, currentToken);

    if (shouldRefresh) {
      try {
        await refreshToken(tokenUsedForRequest: currentToken);
      } on RevokeTokenException catch (_) {
        // Token is already cleared by refreshToken.
      }
      currentToken = await token;
    }

    final canClone = request.canClone;

    final http.BaseRequest outboundRequest;
    if (canClone) {
      outboundRequest = _cloneWithToken(request: request, token: currentToken);
    } else {
      if (currentToken != null) {
        request.headers.addAll(_tokenHeader(currentToken));
      }
      outboundRequest = request;
    }

    final response = await http.Response.fromStream(
      await _httpClient.send(outboundRequest),
    );

    if (!canClone || currentToken == null || !_shouldRefresh(response)) {
      return response.streamed;
    }

    try {
      return await _tryRefresh(request, response, currentToken);
    } on http.ClientException {
      rethrow;
    } catch (_) {
      return response.streamed;
    }
  }

  Future<http.StreamedResponse> _tryRefresh(
    http.BaseRequest originalRequest,
    http.Response response,
    T? tokenUsedForRequest,
  ) async {
    final T refreshedToken;
    try {
      refreshedToken = await refreshToken(
        tokenUsedForRequest: tokenUsedForRequest,
      );
    } on RevokeTokenException catch (error) {
      throw http.ClientException('$error', originalRequest.url);
    }

    return _httpClient.send(
      _cloneWithToken(request: originalRequest, token: refreshedToken),
    );
  }

  /// Creates a copy of [request] with updated authorization headers derived
  /// from [token]. If [token] is null, no auth headers are added.
  http.BaseRequest _cloneWithToken({
    required http.BaseRequest request,
    required T? token,
  }) {
    final tokenHeaders =
        token != null ? _tokenHeader(token) : const <String, String>{};

    if (request is http.Request) {
      return http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..headers.addAll(tokenHeaders)
        ..encoding = request.encoding
        ..bodyBytes = request.bodyBytes;
    }

    if (request is http.MultipartRequest) {
      return http.MultipartRequest(request.method, request.url)
        ..headers.addAll(request.headers)
        ..headers.addAll(tokenHeaders)
        ..fields.addAll(request.fields)
        ..files.addAll(request.files);
    }

    // _cloneWithToken should only be called for known-cloneable types.
    // coverage:ignore-start
    throw UnsupportedError(
      'Cannot clone request of type ${request.runtimeType}. '
      'Only http.Request and http.MultipartRequest are supported.',
    );
    // coverage:ignore-end
  }

  static bool _defaultShouldRefresh(http.Response? response) {
    return response?.statusCode == 401;
  }

  static bool _defaultShouldRefreshBeforeRequest<T>(
    http.BaseRequest request,
    T? token,
  ) {
    if (token is Token) {
      final expiresAt = token.expiresAt;
      if (expiresAt != null) return expiresAt.isBefore(DateTime.now());
    }
    return false;
  }
}

extension on http.BaseRequest {
  /// Whether the current request can safely be cloned.
  bool get canClone => this is http.Request || this is http.MultipartRequest;
}

extension on http.Response {
  /// Wraps a completed [http.Response] into a [http.StreamedResponse].
  http.StreamedResponse get streamed {
    return http.StreamedResponse(
      Stream.value(bodyBytes),
      statusCode,
      contentLength: contentLength,
      request: request,
      headers: headers,
      isRedirect: isRedirect,
      persistentConnection: persistentConnection,
      reasonPhrase: reasonPhrase,
    );
  }
}
