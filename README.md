# Fresh 🍋

[![Pub](https://img.shields.io/pub/v/fresh.svg)](https://pub.dev/packages/fresh)
[![style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://github.com/tenhobi/effective_dart)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

A Dart HTTP Client with built-in token refresh.

## Overview

Fresh is a package which attempts to simplify custom API authentication by integrating token refresh and caching directly into the client. Fresh is flexible and is intended to support custom token refresh mechanisms.

## Usage

### Extend FreshClient

```dart
// 1. Specify the Token Type
class MyHttpClient extends FreshClient<OAuth2Token> {
  // 2. Provide an implementation of `TokenStorage`.
  MyHttpClient() : super(InMemoryTokenStorage());

  @override
  Future<OAuth2Token> refreshToken(token, client) async {
    // 3. Implement token refresh.
  }
}
```

### Make Requests

As requests are made, `FreshClient` will handle managing the token for you. Tokens will be refreshed as needed and requests will be automatically retried pending a successful refresh.

```dart
// Use like a normal Http Client.
final httpClient = MyHttpClient();
final response = await httpClient.get(url, headers: headers);
```

## Example

See [the example](https://github.com/felangel/fresh/tree/master/example) for a complete sample application using `fresh` which integrates with [jsonplaceholder](https://jsonplaceholder.typicode.com).
