# fresh_http 🍋

[![Pub](https://img.shields.io/pub/v/fresh_http.svg)](https://pub.dev/packages/fresh_http)
[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh_http/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License:
MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub
stars](https://img.shields.io/github/stars/felangel/fresh.svg?style=flat&logo=github&label=stars)](https://github.com/felangel/fresh)

---

A [package:http](https://pub.dev/packages/http) client for automatic token
refresh. Handles transparently refreshing, caching, and attaching authentication
tokens to requests.

## Why Fresh?

Token-based authentication seems simple until you handle the edge cases: tokens
expire mid-session, multiple requests fail at the same time triggering duplicate
refreshes, refresh tokens get revoked, and you need to route users to login when
auth is lost. Fresh handles all of this as a drop-in `http.Client` — no changes
to your existing request code required.

## Features

- **Automatic token refresh** on 401 responses, with automatic request retry
- **Proactive refresh** before requests when the token is expired
- **Single-flight refresh** - concurrent requests share one refresh call instead
  of triggering multiple
- **`authenticationStatus` stream** for reacting to login/logout events
- **Pluggable `TokenStorage`** - bring your own persistence layer
- **Built-in `OAuth2Token`** with `expiresAt` support
- **Custom token types** - use any token format with a custom `tokenHeader`
- **Selective auth** - skip token attachment for specific requests via
  `isTokenRequired`

## Quick Start

```dart
final client = Fresh.oAuth2(
  tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
  refreshToken: (token, client) async {
    final response = await client.post(
      Uri.parse('https://api.example.com/auth/refresh'),
      body: {'refresh_token': token?.refreshToken},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

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
);
```

`Fresh.oAuth2` automatically adds `Authorization: bearer <accessToken>` headers.
For custom token types, use the `Fresh()` constructor with a custom
`tokenHeader`:

```dart
final client = Fresh<String>(
  tokenStorage: InMemoryTokenStorage<String>(),
  tokenHeader: (token) => {'x-api-key': token},
  refreshToken: (token, client) async {
    final response = await client.post(
      Uri.parse('https://api.example.com/auth/refresh'),
      body: {'api_key': token},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['api_key'] as String;
  },
);
```

## How It Works

1. **Before each request**: If the token has an `expiresAt` date in the past, it
   is refreshed proactively.
2. **Auth header**: The current token is attached to the request as an
   `Authorization` header.
3. **On 401 response**: The token is refreshed and the request is retried
   automatically.
4. **Concurrent requests**: If multiple requests trigger a refresh
   simultaneously, only one refresh call is made. The others wait for the
   result.

## Authentication Status

Listen to `authenticationStatus` to react to login/logout events, e.g. for
routing:

```dart
final client = Fresh.oAuth2(...);

client.authenticationStatus.listen((status) {
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

`InMemoryTokenStorage` is provided for convenience but tokens are lost on app
restart. For persistence, implement `TokenStorage<T>`:

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
  isTokenRequired: (request) => !request.url.path.contains('/auth/'),
);
```

## Custom HTTP Client for Refresh

Fresh uses a separate `http.Client` for the refresh call to avoid an infinite
loop (your main client is the `Fresh` instance). By default a plain
`http.Client()` is created — this means it does not share base URLs, headers, or
other configuration from your main client. If your `refreshToken` callback uses
absolute URLs this is fine. If you need shared configuration, pass a custom
`httpClient`:

```dart
final client = Fresh.oAuth2(
  tokenStorage: storage,
  httpClient: MyConfiguredClient(),
  refreshToken: (token, client) async {
    // client is MyConfiguredClient - won't trigger Fresh again
    final response = await client.post(
      Uri.parse('https://api.example.com/auth/refresh'),
      body: {'refresh_token': token?.refreshToken},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuth2Token(
      accessToken: body['access_token'],
      refreshToken: body['refresh_token'],
    );
  },
);
```

## Custom Refresh Conditions

The default `shouldRefresh` triggers on any 401 response. In practice, a 401 can
also come from proxies, CDNs, or misconfigured backends that have nothing to do
with your token. Check the response body for a clear indicator instead:

```dart
Fresh.oAuth2(
  tokenStorage: storage,
  refreshToken: refreshToken,
  shouldRefresh: (response) {
    if (response?.statusCode != 401) return false;
    // Only refresh when the server explicitly signals an expired token,
    // not on generic 401s from proxies or other middleware.
    final body = jsonDecode(response!.body);
    if (body is Map<String, dynamic>) {
      return body['error'] == 'token_expired';
    }
    return false;
  },
  shouldRefreshBeforeRequest: (request, token) {
    // Refresh proactively if token expires within 60 seconds.
    // By default, a refresh is performed if the token expires within 30s.
    final expiresAt = token?.expiresAt;
    if (expiresAt == null) return false;
    return expiresAt.difference(DateTime.now()).inSeconds < 60;
  },
);
```

## RevokeTokenException vs other errors

There are two distinct failure modes in `refreshToken`:

- **`RevokeTokenException`**: the refresh token is permanently invalid. Fresh
  clears the stored token, sets `authenticationStatus` to `unauthenticated`, and
  throws an `http.ClientException` to the original caller.
- **Any other exception**: a transient failure (network error, server error,
  etc). Fresh resolves the original 401 response to the caller without retrying,
  and resets internal state so the next request can attempt a fresh refresh.

## Example

See [the
example](https://github.com/felangel/fresh/tree/master/packages/fresh_http/example)
for a complete sample application.
