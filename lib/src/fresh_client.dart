import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:fresh/fresh.dart';
import 'package:http/http.dart' show Client, Request, Response;
import 'package:meta/meta.dart';

import '../fresh.dart';

/// An Exception that should be thrown when overriding `refreshToken` if the
/// refresh fails and should result in a force-logout.
class RevokeTokenException implements Exception {}

/// {@template oauth2_token}
/// Standard OAuth2Token as defined by
/// https://www.oauth.com/oauth2-servers/access-tokens/access-token-response/
/// {@endtemplate}
class OAuth2Token implements Token {
  /// {macro oauth2_token}
  const OAuth2Token({
    @required this.accessToken,
    this.tokenType = 'bearer',
    this.expiresIn,
    this.refreshToken,
    this.scope,
  });

  /// The access token string as issued by the authorization server.
  final String accessToken;

  /// The type of token this is, typically just the string “bearer”.
  final String tokenType;

  /// If the access token expires, the server should reply
  /// with the duration of time the access token is granted for.
  final int expiresIn;

  /// Token which applications can use to obtain another access token.
  final String refreshToken;

  /// Application scope granted as defined in https://oauth.net/2/scope
  final String scope;
}

/// {@template token}
/// Generic Token Interface
/// {@endtemplate}
abstract class Token {
  /// {@macro token}
  const Token();
}

/// Enum representing the current authentication status of the application.
enum AuthenticationStatus {
  /// The status before the true `AuthenticationStatus` has been determined.
  initial,

  /// The status when the application is not authenticated.
  unauthenticated,

  /// The status when the application is authenticated.
  authenticated
}

/// An interface which must be implemented to
/// read, write, and delete the `Token`.
abstract class TokenStorage<T extends Token> {
  /// Returns the stored token asynchronously.
  Future<T> read();

  /// Saves the provided [token] asynchronously.
  Future<void> write(T token);

  /// Deletes the stored token asynchronously.
  Future<void> delete();
}

/// {@template fresh_client}
/// A Dart HTTP Client with built-in token refresh.
/// Requires a concrete implementation of [TokenStorage]
/// and handles transparently refreshing/caching tokens.
///
/// In most cases, [FreshClient] should be extended by a
/// custom HttpClient implementation and the `refreshToken`
/// method must be implemented.
///
/// ```dart
/// class ApiClient extends FreshClient<OAuth2Token> {
///   // Must provide a concrete implementation of `TokenStorage` to super.
///   ApiClient() : super(InMemoryTokenStorage());
///
///   @override
///   Future<OAuth2Token> refreshToken(token, client) async {
///     // Make a token refresh request using the current token
///     // and the provided client and return a new token.
///   }
/// }
/// ```
/// {@endtemplate}
abstract class FreshClient<T extends Token> {
  /// {@macro fresh_client}
  FreshClient(TokenStorage tokenStorage)
      : assert(tokenStorage != null),
        _tokenStorage = tokenStorage {
    _tokenStorage.read().then((token) {
      _token = token;
      _authenticationStatus = token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    });
  }

  static final Client _httpClient = Client();
  static final StreamController _controller =
      StreamController<AuthenticationStatus>()
        ..add(AuthenticationStatus.initial);

  final TokenStorage<T> _tokenStorage;

  T _token;

  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  /// Returns a `Stream<AuthenticationState>` which is updated internally based
  /// on if a valid token exists in [TokenStorage].
  Stream<AuthenticationStatus> get authenticationStatus => _controller.stream;

  /// Returns the desired header which will be added to all outgoing requests.
  /// Defaults to:
  /// ```dart
  /// {
  ///   'authorization': '${token.tokenType} ${token.accessToken}'
  /// }
  /// ```
  /// if token is of type [OAuth2Token].
  ///
  /// This method must be overridden if using a non [OAuth2Token]
  /// otherwise an `UnimplementedError` will be thrown.
  Map<String, String> tokenHeader(T token) {
    if (token is OAuth2Token) {
      return {
        'authorization': '${token.tokenType} ${token.accessToken}',
      };
    }
    throw UnimplementedError();
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the `AuthenticationStatus` accordingly.
  /// If the provided token is null, the `AuthenticationStatus` will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  ///
  /// This method should be called after making a successful token request
  /// from the custom `FreshClient` implementation.
  Future<void> setToken(T token) async {
    await _tokenStorage.write(token);
    _controller.add(
      token == null
          ? AuthenticationStatus.unauthenticated
          : AuthenticationStatus.authenticated,
    );
    _token = token;
  }

  /// Must be overridden and is responsible for returning a new token
  /// given the current token and an http client instance.
  ///
  /// `refreshToken` will be called when `shouldRefresh` returns `true`.
  ///
  /// If a refresh fails, a [RevokeTokenException] should be thrown in order
  /// to invalidate the current token.
  Future<T> refreshToken(T token, Client httpClient);

  /// Returns a `bool` which determines whether `refreshToken` should be called
  /// based on the provided `Response`.
  ///
  /// By default `shouldRefresh` returns `true`
  /// if the response has a 403 status code.
  bool shouldRefresh(Response response) {
    return response.statusCode == HttpStatus.unauthorized;
  }

  /// Sends an HTTP HEAD request with the given headers to the given URL, which
  /// can be a [Uri] or a [String].
  Future<Response> head(dynamic url, {Map<String, String> headers}) {
    return _send('HEAD', url, headers);
  }

  /// Sends an HTTP GET request with the given headers to the given URL, which
  /// can be a [Uri] or a [String].
  Future<Response> get(dynamic url, {Map<String, String> headers}) {
    return _send('GET', url, headers);
  }

  /// Sends an HTTP POST request with the given headers and body to the given
  /// URL, which can be a [Uri] or a [String].
  ///
  /// [body] sets the body of the request. It can be a [String], a [List<int>]
  /// or a [Map<String, String>]. If it's a String, it's encoded using
  /// [encoding] and used as the body of the request. The content-type of the
  /// request will default to "text/plain".
  ///
  /// If [body] is a List, it's used as a list of bytes for the body of the
  /// request.
  ///
  /// If [body] is a Map, it's encoded as form fields using [encoding]. The
  /// content-type of the request will be set to
  /// `"application/x-www-form-urlencoded"`; this cannot be overridden.
  ///
  /// [encoding] defaults to UTF-8.
  Future<Response> post(
    dynamic url, {
    Map<String, String> headers,
    dynamic body,
    Encoding encoding,
  }) {
    return _send('POST', url, headers, body, encoding);
  }

  /// Sends an HTTP PUT request with the given headers and body to the given
  /// URL, which can be a [Uri] or a [String].
  ///
  /// [body] sets the body of the request. It can be a [String], a [List<int>]
  /// or a [Map<String, String>]. If it's a String, it's encoded using
  /// [encoding] and used as the body of the request. The content-type of the
  /// request will default to "text/plain".
  ///
  /// If [body] is a List, it's used as a list of bytes for the body of the
  /// request.
  ///
  /// If [body] is a Map, it's encoded as form fields using [encoding]. The
  /// content-type of the request will be set to
  /// `"application/x-www-form-urlencoded"`; this cannot be overridden.
  ///
  /// [encoding] defaults to UTF-8.
  Future<Response> put(
    dynamic url, {
    Map<String, String> headers,
    dynamic body,
    Encoding encoding,
  }) {
    return _send('PUT', url, headers, body, encoding);
  }

  /// Sends an HTTP PATCH request with the given headers and body to the given
  /// URL, which can be a [Uri] or a [String].
  ///
  /// [body] sets the body of the request. It can be a [String], a [List<int>]
  /// or a [Map<String, String>]. If it's a String, it's encoded using
  /// [encoding] and used as the body of the request. The content-type of the
  /// request will default to "text/plain".
  ///
  /// If [body] is a List, it's used as a list of bytes for the body of the
  /// request.
  ///
  /// If [body] is a Map, it's encoded as form fields using [encoding]. The
  /// content-type of the request will be set to
  /// `"application/x-www-form-urlencoded"`; this cannot be overridden.
  ///
  /// [encoding] defaults to UTF-8.
  Future<Response> patch(
    dynamic url, {
    Map<String, String> headers,
    dynamic body,
    Encoding encoding,
  }) {
    return _send('PATCH', url, headers, body, encoding);
  }

  /// Sends an HTTP DELETE request with the given headers to the given URL,
  /// which can be a [Uri] or a [String].
  Future<Response> delete(dynamic url, {Map<String, String> headers}) {
    return _send('DELETE', url, headers);
  }

  Future<T> _getToken() async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    final token = await _tokenStorage.read();
    _controller.add(
      token != null
          ? AuthenticationStatus.authenticated
          : AuthenticationStatus.unauthenticated,
    );
    _token = token;
    return _token;
  }

  Future<void> _onRevokeTokenException() async {
    await _tokenStorage.delete();
    _token = null;
    _controller.add(AuthenticationStatus.unauthenticated);
  }

  Future<Response> _send(
    String method,
    dynamic url,
    Map<String, String> headers, [
    dynamic body,
    Encoding encoding,
    bool isRetry = false,
  ]) async {
    var request = Request(method, _fromUriOrString(url));
    final token = await _getToken();
    if (token != null) {
      (request.headers ?? <String, String>{}).addAll(tokenHeader(token));
    }
    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    final response = await Response.fromStream(await _httpClient.send(request));

    if (token == null || !shouldRefresh(response) || isRetry) {
      return response;
    }

    T refreshedToken;
    try {
      refreshedToken = await refreshToken(token, _httpClient);
    } on RevokeTokenException catch (_) {
      await _onRevokeTokenException();
      return response;
    }
    await _tokenStorage.write(refreshedToken);
    _token = refreshedToken;
    return await _send(method, url, headers, body, encoding, true);
  }

  Uri _fromUriOrString(uri) => uri is String ? Uri.parse(uri) : uri as Uri;
}
