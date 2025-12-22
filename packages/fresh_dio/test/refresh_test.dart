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

  test('calls refreshToken only once when multiple requests are queued',
      () async {
    var refreshCallCount = 0;

    final mockRefreshClient = Dio()
      ..httpClientAdapter = _MockAdapter(
        (options) {
          return ResponseBody.fromString(
            '{"success": true}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        },
      );

    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      httpClient: mockRefreshClient,
      refreshToken: (token, _) async {
        refreshCallCount++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const OAuth2Token(
          accessToken: 'new.access.token',
          refreshToken: 'new.refresh.token',
        );
      },
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'invalid.token',
        refreshToken: 'refresh.token',
      ),
    );

    final dio = Dio();
    dio.interceptors.add(fresh);
    dio.options.baseUrl = 'http://example.com';
    dio.httpClientAdapter = _MockAdapter(
      (options) {
        if (options.headers.containsKey('authorization')) {
          final auth = options.headers['authorization'] as String;
          if (auth.contains('invalid.token')) {
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        }
        return ResponseBody.fromString(
          '{"success": true}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final futures = <Future<Response<Object?>>>[
      dio.get<Object?>('/1'),
      dio.get<Object?>('/2'),
      dio.get<Object?>('/3'),
    ];

    final responses = await Future.wait(futures);

    for (final response in responses) {
      expect(response.statusCode, equals(200));
    }

    expect(
      refreshCallCount,
      equals(1),
      reason: 'refreshToken should only be called once even with multiple '
          'queued requests',
    );
  });

  test('uses refreshed token for all queued requests after refresh', () async {
    final capturedTokens = <String>[];

    final mockRefreshClient = Dio()
      ..httpClientAdapter = _MockAdapter(
        (options) {
          if (options.headers.containsKey('authorization')) {
            final auth = options.headers['authorization'] as String;
            capturedTokens.add(auth);
          }
          return ResponseBody.fromString(
            '{"success": true}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        },
      );

    final fresh = Fresh.oAuth2(
      tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
      httpClient: mockRefreshClient,
      refreshToken: (token, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const OAuth2Token(
          accessToken: 'new.access.token',
          refreshToken: 'new.refresh.token',
        );
      },
    );

    await fresh.setToken(
      const OAuth2Token(
        accessToken: 'invalid.token',
        refreshToken: 'refresh.token',
      ),
    );

    final dio = Dio();
    dio.interceptors.add(fresh);
    dio.options.baseUrl = 'http://example.com';
    dio.httpClientAdapter = _MockAdapter(
      (options) {
        if (options.headers.containsKey('authorization')) {
          final auth = options.headers['authorization'] as String;
          capturedTokens.add(auth);
          if (auth.contains('invalid.token')) {
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        }
        return ResponseBody.fromString(
          '{"success": true}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      },
    );

    final futures = <Future<Response<Object?>>>[
      dio.get<Object?>('/1'),
      dio.get<Object?>('/2'),
      dio.get<Object?>('/3'),
    ];

    final responses = await Future.wait(futures);

    for (final response in responses) {
      expect(response.statusCode, equals(200));
    }

    expect(
      capturedTokens.length,
      equals(6),
      reason: 'should capture tokens from initial attempts (3) and retries (3)',
    );

    final initialTokens = capturedTokens.sublist(0, 3);
    final retryTokens = capturedTokens.sublist(3);

    for (final token in initialTokens) {
      expect(
        token,
        contains('invalid.token'),
        reason: 'initial requests should use the invalid token',
      );
    }

    for (final token in retryTokens) {
      expect(
        token,
        contains('new.access.token'),
        reason: 'retry requests should use the refreshed token',
      );
    }
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
