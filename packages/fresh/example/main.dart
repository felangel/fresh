// ignore_for_file: avoid_print

import 'package:fresh/fresh.dart';

void main() async {
  final tokenStorage = InMemoryTokenStorage<OAuth2Token>();
  final token = OAuth2Token(
    accessToken: 'access_token',
    refreshToken: 'refresh_token',
    expiresIn: 3600,
    issuedAt: DateTime.now(),
  );

  await tokenStorage.write(token);
  final storedToken = await tokenStorage.read();
  print('Stored token: $storedToken');
  if (storedToken != null) {
    await tokenStorage.delete();
  }

  // Configure appropriate fresh client using `TokenStorage` implementation.
  // For example using [fresh_dio](https://pub.dev/packages/fresh_dio)...
  /// ```dart
  /// final dio = Dio()
  ///   ..interceptors.add(
  ///     Fresh<OAuth2Token>(
  ///       tokenStorage: InMemoryTokenStorage(),
  ///       refreshToken: (token, client) {
  ///         // Perform refresh and return new token
  ///       },
  ///     ),
  ///   );
  // ```
}
