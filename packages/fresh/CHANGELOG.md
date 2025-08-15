# 0.5.0

- **BREAKING**: `OAuth2Token` is now final and cannot be extended
  - Extend `AuthToken` instead of `OAuth2Token` for custom token types
- feat: add `issuedAt` field to `AuthToken` base class
- feat: `setToken` now automatically sets `issuedAt` if not provided
- feat: add `AuthToken.expireDate` getter for token expiration validation
- fix: address race condition in `setToken`/`clearToken` operations
  - Token getter now waits for storage operations to complete
  - Authentication status is set to `undetermined` during token updates

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
