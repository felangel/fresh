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
