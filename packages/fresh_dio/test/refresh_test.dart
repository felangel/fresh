import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:test/test.dart';

void main() {
  test('does not hang when refreshToken throws (onError)', () async {
    final exception = Exception('any error');
    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      refreshToken: (_, __) async => throw exception,
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'access.token.jwt',
        refreshToken: 'refreshToken',
      ),
    );

    final dio = Dio();
    dio.interceptors.add(fresh);
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
    expect(response.statusCode, equals(401));
    expect(
      response.extra['fresh'],
      isA<Map<String, dynamic>>()
          .having((m) => m['message'], 'message', equals('refresh failure'))
          .having((m) => m['error'], 'error', equals(exception))
          .having((m) => m['stack_trace'], 'stack trace', isA<StackTrace>()),
    );
  });

  test('does not hang when refreshToken throws (onResponse)', () async {
    final exception = Exception('any error');
    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      refreshToken: (_, __) async => throw exception,
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'access.token.jwt',
        refreshToken: 'refreshToken',
      ),
    );

    final dio = Dio();
    dio.interceptors.add(fresh);
    dio.options.validateStatus = (_) => true;
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
    expect(response.statusCode, equals(401));
    expect(
      response.extra['fresh'],
      isA<Map<String, dynamic>>()
          .having((m) => m['message'], 'message', equals('refresh failure'))
          .having((m) => m['error'], 'error', equals(exception))
          .having((m) => m['stack_trace'], 'stack trace', isA<StackTrace>()),
    );
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
