import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:test/test.dart';

void main() {
  test('does not hang when refreshToken throws', () async {
    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      refreshToken: (_, __) async {
        throw Exception('any error');
      },
      shouldRefresh: (resp) {
        return true;
      },
      tokenHeader: (_) => {
        'custom-name': 'custom-value',
      },
    );
    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'access.token.jwt',
        refreshToken: 'refreshToken',
      ),
    );

    final dio = Dio();
    dio.interceptors.add(fresh);

    // Create a mock HTTP client adapter that returns 401
    dio.httpClientAdapter = _MockAdapter(
      (options) {
        return ResponseBody.fromString(
          '{"error": "Unauthorized"}',
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final response = await dio.get<Object?>('http://example.com');
    expect(response.statusCode, 401);
  });
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.onFetch);

  final ResponseBody Function(RequestOptions options) onFetch;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return onFetch(options);
  }
}
