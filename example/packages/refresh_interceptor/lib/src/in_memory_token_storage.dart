import 'package:fresh/fresh.dart';

class InMemoryTokenStorage implements TokenStorage<OAuth2Token> {
  OAuth2Token _token;

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<OAuth2Token> read() async {
    return _token;
  }

  @override
  Future<void> write(OAuth2Token token) async {
    _token = token;
  }
}
