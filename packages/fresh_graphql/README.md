# fresh_graphql 🍋

[![Pub](https://img.shields.io/pub/v/fresh_graphql.svg)](https://pub.dev/packages/fresh_graphql)
[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/main.yaml)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh_graphql/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/felangel/fresh.svg?style=flat&logo=github&label=stars)](https://github.com/felangel/fresh)

---

A [graphql](https://pub.dev/packages/graphql) link for automatic token refresh. Handles transparently refreshing, caching, and attaching authentication tokens to GraphQL requests.

## Why Fresh?

Token-based authentication seems simple until you handle the edge cases: tokens expire mid-session, multiple requests fail at the same time triggering duplicate refreshes, refresh tokens get revoked, and you need to route users to login when auth is lost. Fresh handles all of this as a single GraphQL link - no changes to your existing queries or mutations required.

## Features

- **Automatic token refresh** on GraphQL error responses, with automatic request retry
- **Proactive refresh** before requests when the token is expired
- **Single-flight refresh** - concurrent requests share one refresh call instead of triggering multiple
- **`authenticationStatus` stream** for reacting to login/logout events
- **Pluggable `TokenStorage`** - bring your own persistence layer
- **Built-in `OAuth2Token`** with `expiresAt` support
- **Custom token types** - use any token format with a custom `tokenHeader`
- **Custom `shouldRefresh`** - define which GraphQL errors trigger a token refresh

## Quick Start

```dart
import 'dart:convert';

final freshLink = FreshLink.oAuth2(
  tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
  refreshToken: (token, client) async {
    final response = await client.post(
      Uri.parse('https://api.example.com/auth/refresh'),
      body: jsonEncode({'refresh_token': token?.refreshToken}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    // Return null when the refresh token itself is invalid.
    // This clears the stored token and sets authenticationStatus to unauthenticated.
    if (body['error'] == 'refresh_token_revoked' ||
        body['error'] == 'refresh_token_expired') {
      return null;
    }

    return OAuth2Token(
      accessToken: body['access_token'],
      refreshToken: body['refresh_token'],
      // Providing expiresIn and issuedAt enables proactive refresh.
      // Before each request, Fresh checks token.expiresAt and refreshes
      // automatically without waiting for an error response.
      expiresIn: body['expires_in'],
      issuedAt: DateTime.now(),
    );
  },
  shouldRefresh: (response) =>
      response.errors?.any((e) => e.message.contains('UNAUTHENTICATED')) ??
      false,
);

// HttpLink comes from package:gql_http_link
final link = Link.from([freshLink, HttpLink('https://api.example.com/graphql')]);
```

`FreshLink.oAuth2` automatically adds `authorization: bearer <accessToken>` headers. For custom token types, use the `FreshLink()` constructor with a custom `tokenHeader`:

```dart
import 'dart:convert';

final freshLink = FreshLink<String>(
  tokenStorage: InMemoryTokenStorage<String>(),
  tokenHeader: (token) => {'x-api-key': token ?? ''},
  refreshToken: (token, client) async {
    final response = await client.post(
      Uri.parse('https://api.example.com/auth/refresh'),
    );
    return jsonDecode(response.body)['api_key'] as String;
  },
  shouldRefresh: (response) =>
      response.errors?.any((e) => e.message.contains('UNAUTHENTICATED')) ?? false,
);
```

## How It Works

1. **Before each request**: If the token has an `expiresAt` date in the past, it is refreshed proactively.
2. **Auth header**: The current token is attached to the request via `HttpLinkHeaders`.
3. **On error response**: When `shouldRefresh` returns true, the token is refreshed and the request is retried.
4. **Concurrent requests**: If multiple GraphQL streams trigger a refresh simultaneously, only one refresh call is made. The others wait for the result.

## Authentication Status

Listen to `authenticationStatus` to react to login/logout events, e.g. for routing:

```dart
final freshLink = FreshLink.oAuth2(...);

freshLink.authenticationStatus.listen((status) {
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

## Custom Refresh Conditions

The `shouldRefresh` callback determines which GraphQL responses trigger a token refresh. Different backends signal auth failures in different ways - some use error codes, others use specific error messages or extensions:

```dart
FreshLink.oAuth2(
  tokenStorage: storage,
  refreshToken: refreshToken,
  shouldRefresh: (response) {
    return response.errors?.any((e) {
      // Check error extensions for an auth error code
      final code = e.extensions?['code'];
      return code == 'UNAUTHENTICATED' || code == 'FORBIDDEN';
    }) ?? false;
  },
  shouldRefreshBeforeRequest: (request, token) {
    // Refresh proactively if token expires within 30 seconds
    final expiresAt = token?.expiresAt;
    if (expiresAt == null) return false;
    return expiresAt.difference(DateTime.now()).inSeconds < 30;
  },
);
```

## Example

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql/example) for a complete sample application.
