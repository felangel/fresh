# 0.7.1

- fix: concurrent UNAUTHENTICATED errors now trigger exactly one token refresh instead of multiple

# 0.7.0

- feat: `ShouldRefreshBeforeRequest` allows conditional token refresh based on GraphQL request details and token expiration
- feat: automatic token refresh based on expiration before requests
- feat: enhanced token validation with `Token.expiresAt` getter  
- feat: support for custom token validation logic with GraphQL Request context

# 0.6.1

- chore: update copyright year
- chore: add funding to `pubspec.yaml`
- ci: revamp ci setup

# 0.6.0

- **BREAKING**: deps: remove `package:graphql` dependency
- deps: upgrade dependencies
  - `gql_exec: ^1.0.0`
  - `gql_link: ^1.0.0`
  - `http: ^1.0.0`
- docs: minor updates to `LICENSE` and `README`
- chore: adjust dart sdk constraint to `">=2.15.0 <4.0.0"`
- chore: use more strict analysis options

# 0.5.2

- feat: upgrade dependencies
  - `graphql: ^5.0.0`
  - `mocktail: ^0.3.0` (dev)

# 0.5.1

- fix: incorrect usage of `updateContextEntry`

# 0.5.0

- **BREAKING** update to null safety (Dart v2.12.0)

# 0.4.0

- **BREAKING** update to `graphql: ^4.0.0`

# 0.4.0-dev.1

- **BREAKING** update to `graphql: ^4.0.0-beta.5`

# 0.3.0

- **BREAKING**: update to `fresh: ^0.3.0`

# 0.2.0

- **BREAKING** remove `onRefreshFailure` from `FreshLink`
- Add `authenticationStatus` Stream to `FreshLink`

# 0.1.0

Initial Release of the library

- Includes `FreshLink` graphql link with built-in token refresh.
