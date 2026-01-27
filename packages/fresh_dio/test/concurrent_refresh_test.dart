import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:test/test.dart';

void main() {
  group('Concurrent Refresh', () {
    test(
      'refreshToken is called exactly once when 3 parallel requests '
      'all get 401',
      () async {
        var refreshCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();

        // Create a shared mock adapter for both the retry client and main dio
        final mockAdapter = _MockAdapter(
          (options) {
            final isRetry =
                options.headers['authorization'] == 'bearer new.token.jwt';
            if (isRetry) {
              return ResponseBody.fromString(
                '{"success": true}',
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          },
        );

        // Create the httpClient used for retries with the mock adapter
        final retryClient = Dio()..httpClientAdapter = mockAdapter;

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          httpClient: retryClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        final dio = Dio()..httpClientAdapter = mockAdapter;
        dio.interceptors.add(fresh);

        // Launch 3 parallel requests
        final futures = [
          dio.get<Object?>('http://example.com/1'),
          dio.get<Object?>('http://example.com/2'),
          dio.get<Object?>('http://example.com/3'),
        ];

        // Give time for all requests to fail and trigger refresh
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Complete the refresh with a new token
        refreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final responses = await Future.wait(futures);

        // All 3 requests should succeed after refresh
        expect(responses.length, equals(3));
        for (final response in responses) {
          expect(response.statusCode, equals(200));
        }

        // refreshToken must be called exactly once
        expect(refreshCallCount, equals(1));
      },
    );

    test(
      'requests arriving while refresh is in-flight await the same refresh',
      () async {
        var refreshCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();

        final mockAdapter = _MockAdapter(
          (options) {
            final isRetry =
                options.headers['authorization'] == 'bearer new.token.jwt';
            if (isRetry) {
              return ResponseBody.fromString(
                '{"success": true}',
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          },
        );

        final retryClient = Dio()..httpClientAdapter = mockAdapter;

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          httpClient: retryClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        final dio = Dio()..httpClientAdapter = mockAdapter;
        dio.interceptors.add(fresh);

        // Start first request - it will trigger refresh
        final future1 = dio.get<Object?>('http://example.com/1');

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(refreshCallCount, equals(1));

        // Start second request while refresh is in-flight
        final future2 = dio.get<Object?>('http://example.com/2');

        // Wait a bit
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Start third request while refresh is still in-flight
        final future3 = dio.get<Object?>('http://example.com/3');

        // Complete the refresh
        refreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final responses = await Future.wait([future1, future2, future3]);

        // All requests should succeed
        expect(responses.length, equals(3));
        for (final response in responses) {
          expect(response.statusCode, equals(200));
        }

        // refreshToken must still be called exactly once
        expect(refreshCallCount, equals(1));
      },
    );

    test(
      'RevokeTokenException: refresh called once, token revoked once, '
      'all requests complete without hanging',
      () async {
        var refreshCallCount = 0;
        var revokeCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>();

        final mockAdapter = _MockAdapter(
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

        final retryClient = Dio()..httpClientAdapter = mockAdapter;

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          httpClient: retryClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        // Track delete calls
        tokenStorage.onDelete = () => revokeCallCount++;

        final dio = Dio()..httpClientAdapter = mockAdapter;
        dio.interceptors.add(fresh);

        // Launch 3 parallel requests
        final futures = [
          dio.get<Object?>('http://example.com/1'),
          dio.get<Object?>('http://example.com/2'),
          dio.get<Object?>('http://example.com/3'),
        ];

        // Give time for requests to trigger refresh
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Complete the refresh with RevokeTokenException
        refreshCompleter.completeError(RevokeTokenException());

        // All requests should complete (not hang)
        final responses = await Future.wait(
          futures.map(
            (f) => f.then<Response<Object?>?>(
              (r) => r,
              onError: (Object e) => (e as DioException).response,
            ),
          ),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'Requests hung after RevokeTokenException',
          ),
        );

        expect(responses.length, equals(3));

        // refreshToken must be called exactly once
        expect(refreshCallCount, equals(1));

        // token should be revoked exactly once
        expect(revokeCallCount, equals(1));
      },
    );

    test(
      'refresh throws other exception: state resets, no hang',
      () async {
        var refreshCallCount = 0;
        final firstRefreshCompleter = Completer<OAuth2Token>();
        final secondRefreshCompleter = Completer<OAuth2Token>();

        final mockAdapter = _MockAdapter(
          (options) {
            final isRetry =
                options.headers['authorization'] == 'bearer new.token.jwt';
            if (isRetry) {
              return ResponseBody.fromString(
                '{"success": true}',
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          },
        );

        final retryClient = Dio()..httpClientAdapter = mockAdapter;

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            if (refreshCallCount == 1) {
              return firstRefreshCompleter.future;
            }
            return secondRefreshCompleter.future;
          },
          httpClient: retryClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        final dio = Dio()..httpClientAdapter = mockAdapter;
        dio.interceptors.add(fresh);
        dio.options.validateStatus = (_) => true;

        // First request triggers refresh that will fail
        final future1 = dio.get<Object?>('http://example.com/1');

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Complete refresh with generic exception
        firstRefreshCompleter.completeError(Exception('Network error'));

        // First request should complete (with 401 response + fresh error info)
        final response1 = await future1.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Request hung'),
        );
        expect(response1.statusCode, equals(401));
        expect(response1.extra['fresh'], isNotNull);

        // State should be reset - second request should trigger new refresh
        final future2 = dio.get<Object?>('http://example.com/2');

        // Wait for second refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(refreshCallCount, equals(2));

        // Complete second refresh successfully
        secondRefreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final response2 = await future2;
        expect(response2.statusCode, equals(200));
      },
    );

    test(
      'after successful refresh, a later 401 triggers a new refresh',
      () async {
        var refreshCallCount = 0;
        var requestCount = 0;
        var currentToken = const OAuth2Token(
          accessToken: 'initial.token.jwt',
          refreshToken: 'refreshToken',
        );

        final mockAdapter = _MockAdapter(
          (options) {
            requestCount++;
            final authHeader = options.headers['authorization'] as String?;
            // First 2 requests (initial + retry after first refresh) succeed
            // Third request (with token-1) fails to simulate expiry
            // Fourth request (retry with token-2) succeeds
            if (authHeader == 'bearer token-1.jwt' && requestCount == 2) {
              return ResponseBody.fromString(
                '{"success": true}',
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            } else if (authHeader == 'bearer token-2.jwt') {
              return ResponseBody.fromString(
                '{"success": true}',
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              '{"error": "Unauthorized"}',
              401,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          },
        );

        final retryClient = Dio()..httpClientAdapter = mockAdapter;

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            return currentToken = OAuth2Token(
              accessToken: 'token-$refreshCallCount.jwt',
              refreshToken: 'refreshToken',
            );
          },
          httpClient: retryClient,
        );

        await fresh.setToken(currentToken);

        final dio = Dio()..httpClientAdapter = mockAdapter;
        dio.interceptors.add(fresh);

        // First request - gets 401, triggers first refresh, retry succeeds
        final response1 = await dio.get<Object?>('http://example.com/1');
        expect(response1.statusCode, equals(200));
        expect(refreshCallCount, equals(1));

        // Wait a bit between requests
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Second request - gets 401 (simulating token expiry),
        // triggers second refresh
        final response2 = await dio.get<Object?>('http://example.com/2');
        expect(response2.statusCode, equals(200));
        expect(refreshCallCount, equals(2));
      },
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

class _TrackingTokenStorage<T> implements TokenStorage<T> {
  T? _token;
  void Function()? onDelete;

  @override
  Future<void> delete() async {
    _token = null;
    onDelete?.call();
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
