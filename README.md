# Fresh 🍋

[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/main.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/felangel/fresh.svg?style=flat&logo=github&label=stars)](https://github.com/felangel/fresh)

---

A collection of packages for automatic token refresh in Dart and Flutter. Fresh handles refreshing, caching, and attaching authentication tokens transparently so your API calls just work.

## Why Fresh?

Token-based authentication seems simple until you handle the edge cases: tokens expire mid-session, multiple requests fail at the same time triggering duplicate refreshes, refresh tokens get revoked, and you need to route users to login when auth is lost. Fresh handles all of this so you don't have to.

- No more manual 401 handling scattered across your codebase
- No more race conditions when concurrent requests trigger simultaneous refreshes
- No more stale tokens causing request failures - expired tokens are refreshed proactively before the request is even sent

## Packages

| Package                                                                               | Pub                                                                                                      |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [fresh](https://github.com/felangel/fresh/tree/master/packages/fresh)                 | [![pub package](https://img.shields.io/pub/v/fresh.svg)](https://pub.dev/packages/fresh)                 |
| [fresh_dio](https://github.com/felangel/fresh/tree/master/packages/fresh_dio)         | [![pub package](https://img.shields.io/pub/v/fresh_dio.svg)](https://pub.dev/packages/fresh_dio)         |
| [fresh_graphql](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql) | [![pub package](https://img.shields.io/pub/v/fresh_graphql.svg)](https://pub.dev/packages/fresh_graphql) |

## Features

- **Automatic token refresh** on 401 / auth errors, with automatic request retry
- **Proactive refresh** before requests when the token is expired
- **Single-flight refresh** - concurrent requests share one refresh call instead of triggering multiple
- **`authenticationStatus` stream** for reacting to login/logout events
- **Pluggable `TokenStorage`** - bring your own persistence layer
- **Built-in `OAuth2Token`** with `expiresAt` support

## Usage

### fresh_dio

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
      return OAuth2Token(
        accessToken: response.data['access_token'],
        refreshToken: response.data['refresh_token'],
      );
    },
  ),
);
```

See the [fresh_dio README](https://github.com/felangel/fresh/tree/master/packages/fresh_dio) for full documentation.

### fresh_graphql

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
    return OAuth2Token(
      accessToken: body['access_token'],
      refreshToken: body['refresh_token'],
    );
  },
  shouldRefresh: (response) =>
      response.errors?.any((e) => e.message.contains('UNAUTHENTICATED')) ?? false,
);

// HttpLink comes from package:gql_http_link
final link = Link.from([freshLink, HttpLink('https://api.example.com/graphql')]);
```

See the [fresh_graphql README](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql) for full documentation.
