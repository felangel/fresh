import 'package:fresh/fresh.dart';

class InMemoryTokenStorage<T extends Token> implements TokenStorage<T> {
  T? _token;

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<T?> read() async {
    return _token;
  }

  @override
  Future<void> write(T token) async {
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
