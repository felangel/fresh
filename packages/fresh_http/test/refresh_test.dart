import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('does not hang when refreshToken throws', () async {
    final exception = Exception('any error');

    var requestCount = 0;
    final spyClient = _SpyClient((_) {
      requestCount++;
      return http.Response('{"error": "Unauthorized"}', 401);
    });

    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      refreshToken: (_, __) async => throw exception,
      httpClient: spyClient,
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'access.token.jwt',
        refreshToken: 'refreshToken',
      ),
    );

    final response = await fresh.get(Uri.parse('http://example.com'));
    expect(response.statusCode, equals(401));
    expect(requestCount, equals(1));
  });

  test('does not attempt refresh when isTokenRequired returns false', () async {
    var refreshCallCount = 0;

    var requestCount = 0;
    final spyClient = _SpyClient((request) {
      requestCount++;
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('{"error": "Unauthorized"}', 401);
    });

    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      refreshToken: (_, __) async {
        refreshCallCount++;
        throw Exception('should not be called');
      },
      isTokenRequired: (_) => false,
      httpClient: spyClient,
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'access.token.jwt',
        refreshToken: 'refreshToken',
      ),
    );

    final response = await fresh.get(Uri.parse('http://example.com'));
    expect(response.statusCode, equals(401));
    expect(refreshCallCount, equals(0), reason: 'Should not attempt refresh');
    expect(requestCount, equals(1));
  });
}

class _SpyClient extends http.BaseClient {
  _SpyClient(this._handler);

  final http.Response Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
