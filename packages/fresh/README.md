# fresh 🍋

[![Pub](https://img.shields.io/pub/v/fresh.svg)](https://pub.dev/packages/fresh)
[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/main.yaml)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/felangel/fresh.svg?style=flat&logo=github&label=stars)](https://github.com/felangel/fresh)

---

An token refresh library for dart. This package exposes the core components that are common to various refresh token implementations (REST, GraphQL, etc...).

**Most users should use one of the integration packages instead:**

| Package | For |
| --- | --- |
| [fresh_dio](https://pub.dev/packages/fresh_dio) | [dio](https://pub.dev/packages/dio) HTTP client |
| [fresh_graphql](https://pub.dev/packages/fresh_graphql) | [gql_link](https://pub.dev/packages/gql_link) GraphQL |

Use `package:fresh` directly only if you are building a custom integration (e.g. for `package:http` or another HTTP client).

## What's Included

- `FreshMixin<T>` - Mixin providing token lifecycle management and single-flight refresh coordination
- `TokenStorage<T>` - Interface for reading, writing, and deleting tokens
- `InMemoryTokenStorage<T>` - Simple in-memory storage implementation
- `Token` / `OAuth2Token` - Base token class and standard OAuth2 token with `expiresAt` support
- `AuthenticationStatus` - Stream-based auth state (`initial`, `authenticated`, `unauthenticated`)
- `RevokeTokenException` - Throw from `performTokenRefresh` to clear the token and signal logout

## Building a Custom Integration

Implement `performTokenRefresh` on a class using `FreshMixin`:

```dart
class MyHttpFresh extends MyHttpClient with FreshMixin<OAuth2Token> {
  MyHttpFresh({required TokenStorage<OAuth2Token> tokenStorage}) {
    this.tokenStorage = tokenStorage;
  }

  @override
  Future<OAuth2Token> performTokenRefresh(OAuth2Token? token) async {
    final response = await post('/auth/refresh', body: {'refresh_token': token?.refreshToken});
    return OAuth2Token(
      accessToken: response['access_token'],
      refreshToken: response['refresh_token'],
    );
  }

  Future<Response> authenticatedRequest(String path) async {
    var currentToken = await token;

    final response = await get(path, headers: {'Authorization': 'Bearer ${currentToken?.accessToken}'});

    if (response.statusCode == 401) {
      final refreshed = await refreshToken(tokenUsedForRequest: currentToken);
      return get(path, headers: {'Authorization': 'Bearer ${refreshed.accessToken}'});
    }

    return response;
  }
}
```

`refreshToken()` handles deduplication automatically - concurrent calls share a single in-flight refresh.
