import 'package:fresh/fresh.dart';

class InMemoryTokenStorage implements TokenStorage<OAuth2Token> {
  OAuth2Token? _token;

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<OAuth2Token?> read() async {
    return _token;
  }

  @override
  Future<void> write(OAuth2Token token) async {
    _token = token;
  }
}

void main() {
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
