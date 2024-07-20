# 0.4.2

- feat: add `assert` to prevent infinite refresh loop
- fix: tighten `package:dio` version constraint
- chore: update copyright year
- chore: add funding to `pubspec.yaml`
- ci: revamp ci setup

# 0.4.1

- fix: replace `Interceptor` with `QueuedInterceptor`
- refactor: use `DioException` instead of deprecated `DioError`
- docs: minor updates to `LICENSE` and `README`
- chore: adjust dart sdk constraint to `">=2.15.0 <4.0.0"`
- chore: use more strict analysis options
- chore: various updates to example app

# 0.4.0

- feat: upgrade to `dio ^0.5.0`
- feat: upgrade dart to `sdk: ">=2.15.0 <3.0.0"`

# 0.3.2

- feat: add httpClient parameter to Fresh.oAuth2 ([#60](https://github.com/felangel/fresh/issues/60))
- chore: upgrade dev dependencies
  - `mocktail: ^0.3.0`
  - `very_good_analysis: ^2.4.0`

# 0.3.1

- fix: remove httpClient lock and add token header to refresh

# 0.3.0

- **BREAKING**: update to `dio: ^4.0.0`
- fix: queue concurrent requests during refresh

# 0.3.0-nullsafety.0

- **BREAKING**: update to dart 2.12 with null safety
- **BREAKING**: update to `fresh: ^0.4.0`
- **BREAKING**: update to `dio: ^4.0.0-beta7`

# 0.2.0

- **BREAKING**: update to `fresh: ^0.3.0`
- fix: throw `DioError` on `RevokeTokenException` ([#26](https://github.com/felangel/fresh/issues/26))

# 0.1.3

- fix: handle `null` response in `onResponse` ([#24](https://github.com/felangel/fresh/pull/24)).

# 0.1.2

- fix: add generic `<T>` parameter to `TokenHeaderBuilder` ([#22](https://github.com/felangel/fresh/pull/22)).

# 0.1.1

- Update to `fresh v0.2.1`

# 0.1.0

Initial Release of the library (copy of package:fresh v0.2.0)

- Includes `Fresh` interceptor with built-in token refresh.
