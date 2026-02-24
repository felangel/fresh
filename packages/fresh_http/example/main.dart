// ignore_for_file: avoid_print
import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final client = Fresh.oAuth2(
    tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
    refreshToken: (token, httpClient) async {
      // In practice, you would fetch a refresh token from your own auth server:
      // ```dart
      // final response = await httpClient.post(
      //   Uri.parse('https://auth.example.com/token'),
      //   body: {'refresh_token': token?.refreshToken},
      // );
      // ```
      // return OAuth2Token.fromJson(jsonDecode(response.body));
      return const OAuth2Token(
        accessToken: 'accessToken',
        refreshToken: 'refreshToken',
      );
    },
  );

  // Listen to authentication status changes.
  final subscription = client.authenticationStatus.listen(print);

  // Simulate a login by storing the initial token.
  await client.setToken(
    const OAuth2Token(
      accessToken: 'initial-access-token',
      refreshToken: 'initial-refresh-token',
    ),
  );

  // Make an authenticated request. Fresh will automatically handle adding an
  // authorization header with a valid token.
  try {
    final response = await client.get(
      Uri.parse('https://jsonplaceholder.typicode.com/todos/1'),
    );
    print('status: ${response.statusCode}');
  } on http.ClientException catch (e) {
    print('request failed: $e');
  }

  // Simulate a logout by clear the token.
  await client.clearToken();

  // Requests made without a token will have no Authorization header.
  try {
    final response = await client.get(
      Uri.parse('https://jsonplaceholder.typicode.com/todos/1'),
    );
    print('status: ${response.statusCode}');
  } on http.ClientException catch (e) {
    print('request failed: $e');
  }

  await client.close();
  await subscription.cancel();
}
