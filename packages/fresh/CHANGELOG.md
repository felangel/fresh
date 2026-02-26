# 0.6.1.

- fix: guard authenticationStatus emits on whether internal controller is closed
- fix: minor analysis warnings

# 0.6.0

- **BREAKING**: `FreshMixin` now requires implementing `performTokenRefresh(T? token)` for raw refresh logic ([#130](https://github.com/felangel/fresh/pull/130))
- feat: add `FreshMixin.refreshToken()` for single-flight token refresh coordination - concurrent refresh attempts share one in-flight operation ([#126](https://github.com/felangel/fresh/issues/126), [#130](https://github.com/felangel/fresh/pull/130))
- fix: race condition in `setToken()`/`clearToken()`/`revokeToken()` where concurrent `token` getter reads returned stale values during storage write ([#115](https://github.com/felangel/fresh/issues/115), [#136](https://github.com/felangel/fresh/pull/136))
- fix: `token` getter avoids unnecessary microtask gap via `Future.sync()` ([#136](https://github.com/felangel/fresh/pull/136))
- fix: `tokenStorage` setter skips initial storage read when `setToken`/`clearToken`/`revokeToken` was already called ([#136](https://github.com/felangel/fresh/pull/136))

# 0.5.0

- feat: add `Token` base class for token extensibility
- feat: add `OAuth2Token.issuedAt` field for token issue date tracking
- feat: add `Token.expiresAt` getter for token expiration validation

# 0.4.4

- refactor: minor adjustment to generics in test
- chore(deps): upgrade to mocktail ^1.0.0

# 0.4.3

- fix: wait for initial storage read before returning token
- chore: update copyright year
- chore: add funding to `pubspec.yaml`
- ci: revamp ci setup

# 0.4.2

- chore: adjust dart sdk constraint to `">=2.12.0 <4.0.0"`
- chore: use more strict analysis options

# 0.4.1

- chore: upgrade dev dependencies
  - upgrade to `mocktail ^0.3.0`

# 0.4.0

- **BREAKING**: Migrate to Dart 2.12.0 with Null Safety

# 0.3.0

- **BREAKING**: Remove `Token` interface
- refactor: `FreshMixin` internal implementation improvements

# 0.2.1

- Add `InMemoryTokenStorage`
- Add `TokenHeaderBuilder` typedef

# 0.2.0

- **BREAKING**: split `dio` interceptor into separate package (`fresh_dio`)
  - `package:fresh` is repurposed to contain core refresh components

# 0.1.0

- Improvements to internal implementation
- Fully Unit Tested

# 0.0.3

- Fix: expose DioErrors to shouldRefresh function ([#9](https://github.com/felangel/fresh/issues/9))

# 0.0.2

- **BREAKING**: convert to [dio](https://pub.dev/packages/dio) interceptor.

# 0.0.1

Initial Release of the library.

- Includes `FreshClient` with built-in token refresh.
