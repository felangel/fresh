# fresh_dio 🍋

[![Pub](https://img.shields.io/pub/v/fresh_dio.svg)](https://pub.dev/packages/fresh_dio)
[![fresh_dio](https://github.com/felangel/fresh/actions/workflows/fresh_dio.yaml/badge.svg)](https://github.com/felangel/fresh/actions/workflows/fresh_dio.yaml)
[![coverage](https://raw.githubusercontent.com/felangel/fresh/master/packages/fresh_dio/coverage_badge.svg)](https://github.com/felangel/fresh/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

A [dio](https://pub.dev/packages/dio) interceptor for built-in token refresh. Built to be used with [fresh](https://pub.dev/packages/fresh).

## Overview

`fresh_dio` is a [dio](https://pub.dev/packages/dio) interceptor which attempts to simplify custom API authentication by integrating token refresh and caching transparently. `fresh_dio` is flexible and is intended to support custom token refresh mechanisms.

## Usage

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

## Example

See [the example](https://github.com/felangel/fresh/tree/master/packages/fresh_dio/example) for a complete sample application using `fresh_dio` which integrates with [jsonplaceholder](https://jsonplaceholder.typicode.com).
