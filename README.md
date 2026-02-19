# Fresh 🍋

[![build](https://github.com/felangel/fresh/actions/workflows/main.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/main.yaml)
[![coverage](./packages/fresh/coverage_badge.svg)](https://github.com/felangel/fresh/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

A token refresh library for Dart. This library consists of a collection of packages which specialize in a particular aspect of token refresh.

## Packages

| Package                                                                               | Pub                                                                                                      |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [fresh](https://github.com/felangel/fresh/tree/master/packages/fresh)                 | [![pub package](https://img.shields.io/pub/v/fresh.svg)](https://pub.dev/packages/fresh)                 |
| [fresh_dio](https://github.com/felangel/fresh/tree/master/packages/fresh_dio)         | [![pub package](https://img.shields.io/pub/v/fresh_dio.svg)](https://pub.dev/packages/fresh_dio)         |
| [fresh_graphql](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql) | [![pub package](https://img.shields.io/pub/v/fresh_graphql.svg)](https://pub.dev/packages/fresh_graphql) |

## Overview

`fresh` attempts to simplify custom API authentication by integrating token refresh and caching transparently. It is flexible and intended to support custom token refresh mechanisms.

## Usage

### fresh_dio

A [dio](https://pub.dev/packages/dio) interceptor for built-in token refresh.

```dart
dio.interceptors.add(
  Fresh.oAuth2(
    tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
    refreshToken: (token, client) {
      // Perform refresh and return new token
    },
  ),
);
```

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_dio/example) for a complete sample application using `fresh_dio` which integrates with [jsonplaceholder](https://jsonplaceholder.typicode.com).

### fresh_graphql

A [graphql](https://pub.dev/packages/graphql) link for built-in token refresh.

```dart
final freshLink = FreshLink.oAuth2(
  tokenStorage: InMemoryTokenStorage(),
  refreshToken: (token, client) {
    // Perform refresh and return new token
  },
);
final graphQLClient = GraphQLClient(
  cache: InMemoryCache(),
  link: Link.from([freshLink, HttpLink(uri: 'https://my.graphql.api')]),
);
```

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql/example) for a complete sample application using `fresh_graphql` which integrates with [api.graphql.jobs](https://api.graphql.jobs).
