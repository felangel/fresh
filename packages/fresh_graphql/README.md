# fresh_graphql 🍋

[![Pub](https://img.shields.io/pub/v/fresh_graphql.svg)](https://pub.dev/packages/fresh_graphql)
[![build](https://github.com/felangel/fresh/workflows/build/badge.svg)](https://github.com/felangel/fresh/actions)
[![coverage](https://github.com/felangel/fresh/blob/master/packages/fresh_graphql/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://github.com/tenhobi/effective_dart)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

A [graphql](https://pub.dev/packages/graphql) link for built-in token refresh. Built to be used with [fresh](https://pub.dev/packages/fresh).

## Overview

`fresh_graphql` is a [graphql](https://pub.dev/packages/graphql) link which attempts to simplify custom API authentication by integrating token refresh and caching transparently. `fresh_graphql` is flexible and is intended to support custom token refresh mechanisms.

## Usage

```dart
final freshLink = FreshLink(
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

## Example

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql/example) for a complete sample application using `fresh_graphql` which integrates with [api.graphql.jobs](https://api.graphql.jobs).
