# fresh_dio 🍋

[![Pub](https://img.shields.io/pub/v/fresh_dio.svg)](https://pub.dev/packages/fresh_dio)
[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/main.yaml)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh_dio/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/felangel/fresh.svg?style=flat&logo=github&label=stars)](https://github.com/felangel/fresh)

---

A [dio](https://pub.dev/packages/dio) interceptor for automatic token refresh. Handles transparently refreshing, caching, and attaching authentication tokens to requests.

## Why Fresh?

Token-based authentication seems simple until you handle the edge cases: tokens expire mid-session, multiple requests fail at the same time triggering duplicate refreshes, refresh tokens get revoked, and you need to route users to login when auth is lost. Fresh handles all of this as a single dio interceptor - no changes to your existing request code required.

## Features

- **Automatic token refresh** on 401 responses, with automatic request retry
- **Proactive refresh** before requests when the token is expired
- **Single-flight refresh** - concurrent requests share one refresh call instead of triggering multiple
- **`authenticationStatus` stream** for reacting to login/logout events
- **Pluggable `TokenStorage`** - bring your own persistence layer
- **Built-in `OAuth2Token`** with `expiresAt` support
- **Custom token types** - use any token format with a custom `tokenHeader`
- **Selective auth** - skip token attachment for specific requests via `isTokenRequired`

## Quick Start

```dart
final dio = Dio();

dio.interceptors.add(
  Fresh.oAuth2(
    tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
    refreshToken: (token, client) async {
      final response = await client.post(
        'https://api.example.com/auth/refresh',
        data: {'refresh_token': token?.refreshToken},
      );
      final body = response.data as Map<String, dynamic>;

      // Throw RevokeTokenException when the refresh token itself is invalid.
      // This clears the stored token and sets authenticationStatus to unauthenticated.
      // Don't rely on status codes alone - check the body for a clear signal.
      if (body['error'] == 'refresh_token_revoked' ||
          body['error'] == 'refresh_token_expired') {
        throw RevokeTokenException();
      }

      return OAuth2Token(
        accessToken: body['access_token'],
        refreshToken: body['refresh_token'],
        // Providing expiresIn and issuedAt enables proactive refresh.
        // Before each request, Fresh checks token.expiresAt and refreshes
        // automatically without waiting for a 401.
        expiresIn: body['expires_in'],
        issuedAt: DateTime.now(),
      );
    },
  ),
);
```

`Fresh.oAuth2` automatically adds `Authorization: bearer <accessToken>` headers. For custom token types, use the `Fresh()` constructor with a custom `tokenHeader`:

```dart
dio.interceptors.add(
  Fresh<String>(
    tokenStorage: InMemoryTokenStorage<String>(),
    tokenHeader: (token) => {'x-api-key': token},
    refreshToken: (token, client) async {
      final response = await client.post(
        'https://api.example.com/auth/refresh',
        data: {'api_key': token},
      );
      return response.data['api_key'] as String;
    },
  ),
);
```

## How It Works

1. **Before each request**: If the token has an `expiresAt` date in the past, it is refreshed proactively.
2. **Auth header**: The current token is attached to the request as an `Authorization` header.
3. **On 401 response**: The token is refreshed and the request is retried automatically.
4. **Concurrent requests**: If multiple requests trigger a refresh simultaneously, only one refresh call is made. The others wait for the result.

## Authentication Status

Listen to `authenticationStatus` to react to login/logout events, e.g. for routing:

```dart
final fresh = Fresh.oAuth2(...);

fresh.authenticationStatus.listen((status) {
  switch (status) {
    case AuthenticationStatus.authenticated:
      // navigate to home
    case AuthenticationStatus.unauthenticated:
      // navigate to login
    case AuthenticationStatus.initial:
      // show splash
  }
});
```

## Token Storage

`InMemoryTokenStorage` is provided for convenience but tokens are lost on app restart. For persistence, implement `TokenStorage<T>`:

```dart
class SecureTokenStorage implements TokenStorage<OAuth2Token> {
  @override
  Future<OAuth2Token?> read() async { /* read from secure storage */ }

  @override
  Future<void> write(OAuth2Token token) async { /* write to secure storage */ }

  @override
  Future<void> delete() async { /* delete from secure storage */ }
}
```

## Skipping Auth for Specific Requests

Use `isTokenRequired` to exclude endpoints like login or public APIs:

```dart
Fresh.oAuth2(
  tokenStorage: storage,
  refreshToken: refreshToken,
  isTokenRequired: (options) => !options.path.contains('/auth/'),
);
```

## Custom HTTP Client for Refresh

Fresh uses a separate `Dio` instance for the refresh call to avoid an infinite loop (your main Dio has Fresh as interceptor). By default a plain `Dio()` is created - this means it does not share `baseUrl`, headers, or other options from your main Dio. If your `refreshToken` callback uses relative paths, pass a custom `httpClient` with the same `baseUrl`:

```dart
final refreshDio = Dio()..options.baseUrl = 'https://api.example.com';

dio.interceptors.add(
  Fresh.oAuth2(
    tokenStorage: storage,
    httpClient: refreshDio,
    refreshToken: (token, client) async {
      // client is refreshDio - won't trigger Fresh again
      final response = await client.post(
        '/auth/refresh',
        data: {'refresh_token': token?.refreshToken},
      );
      return OAuth2Token(
        accessToken: response.data['access_token'],
        refreshToken: response.data['refresh_token'],
      );
    },
  ),
);
```

## Custom Refresh Conditions

The default `shouldRefresh` triggers on any 401 response. In practice, a 401 can also come from proxies, CDNs, or misconfigured backends that have nothing to do with your token. Check the response body for a clear indicator instead:

```dart
Fresh.oAuth2(
  tokenStorage: storage,
  refreshToken: refreshToken,
  shouldRefresh: (response) {
    if (response?.statusCode != 401) return false;
    // Only refresh when the server explicitly signals an expired token,
    // not on generic 401s from proxies or other middleware.
    final body = response?.data;
    if (body is Map<String, dynamic>) {
      return body['error'] == 'token_expired';
    }
    return false;
  },
  shouldRefreshBeforeRequest: (options, token) {
    // Refresh proactively if token expires within 60 seconds
    // By default, a refresh is performed if the token expires within 30s.
    final expiresAt = token?.expiresAt;
    if (expiresAt == null) return false;
    return expiresAt.difference(DateTime.now()).inSeconds < 60;
  },
);
```

## Example

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_dio/example) for a complete sample application.
