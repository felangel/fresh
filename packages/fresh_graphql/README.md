# fresh_graphql 🍋

[![Pub](https://img.shields.io/pub/v/fresh_graphql.svg)](https://pub.dev/packages/fresh_graphql)
[![fresh_graphql](https://github.com/felangel/fresh/actions/workflows/fresh_graphql.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/fresh_graphql.yaml)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh_graphql/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

A [graphql](https://pub.dev/packages/graphql) link for built-in token refresh. Built to be used with [fresh](https://pub.dev/packages/fresh).

## Overview

`fresh_graphql` is a [graphql](https://pub.dev/packages/graphql) link which attempts to simplify custom API authentication by integrating token refresh and caching transparently. `fresh_graphql` is flexible and is intended to support custom token refresh mechanisms.

## Usage

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

## Example

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_graphql/example) for a complete sample application using `fresh_graphql` which integrates with [api.graphql.jobs](https://api.graphql.jobs).
