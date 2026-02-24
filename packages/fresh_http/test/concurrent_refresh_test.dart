import 'dart:async';

import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('Concurrent Refresh', () {
    test(
      'refreshToken is called exactly once when 3 parallel requests '
      'all get 401',
      () async {
        var refreshCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();

        final mockClient = _mockClient((request) {
          final isRetry =
              request.headers['authorization'] == 'bearer new.token.jwt';
          if (isRetry) {
            return http.Response(
              '{"success": true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error": "Unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final retryClient = mockClient;

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

        // Launch 3 parallel requests
        final futures = [
          fresh.get(Uri.parse('http://example.com/1')),
          fresh.get(Uri.parse('http://example.com/2')),
          fresh.get(Uri.parse('http://example.com/3')),
        ];

        // Give time for all requests to fail and trigger refresh
        await pumpEventQueue();

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

        final mockClient = _mockClient((request) {
          final isRetry =
              request.headers['authorization'] == 'bearer new.token.jwt';
          if (isRetry) {
            return http.Response(
              '{"success": true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error": "Unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          httpClient: mockClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        // Start first request - it will trigger refresh
        final future1 = fresh.get(Uri.parse('http://example.com/1'));

        // Wait for refresh to be triggered
        await pumpEventQueue();
        expect(refreshCallCount, equals(1));

        // Start second request while refresh is in-flight
        final future2 = fresh.get(Uri.parse('http://example.com/2'));

        // Wait a bit
        await pumpEventQueue();

        // Start third request while refresh is still in-flight
        final future3 = fresh.get(Uri.parse('http://example.com/3'));

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

        final mockClient = _mockClient((request) {
          return http.Response(
            '{"error": "Unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          httpClient: mockClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        // Track delete calls
        tokenStorage.onDelete = () => revokeCallCount++;

        // Launch 3 parallel requests
        final futures = [
          fresh.get(Uri.parse('http://example.com/1')),
          fresh.get(Uri.parse('http://example.com/2')),
          fresh.get(Uri.parse('http://example.com/3')),
        ];

        // Give time for requests to trigger refresh
        await pumpEventQueue();

        // Complete the refresh with RevokeTokenException
        refreshCompleter.completeError(RevokeTokenException());

        // All requests should complete (not hang).
        // On RevokeTokenException the http version throws http.ClientException,
        // so we catch it and treat it as a null response (mirroring the Dio
        // version catching DioException and reading .response).
        final responses = await Future.wait(
          futures.map(
            (f) => f.then<http.Response?>(
              (r) => r,
              // ignore: only_throw_errors
              onError: (Object e) => e is http.ClientException ? null : throw e,
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

        final mockClient = _mockClient((request) {
          final isRetry =
              request.headers['authorization'] == 'bearer new.token.jwt';
          if (isRetry) {
            return http.Response(
              '{"success": true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error": "Unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            if (refreshCallCount == 1) {
              return firstRefreshCompleter.future;
            }
            return secondRefreshCompleter.future;
          },
          httpClient: mockClient,
        );

        await fresh.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        // First request triggers refresh that will fail.
        // Unlike Dio (validateStatus: (_) => true), package:http always gives
        // us the response object, so no special config is needed here.
        final future1 = fresh.get(Uri.parse('http://example.com/1'));

        // Wait for refresh to be triggered
        await pumpEventQueue();

        // Complete refresh with generic exception
        firstRefreshCompleter.completeError(Exception('Network error'));

        // First request should complete with the original 401 response.
        // The http version resolves with the buffered response on non-revoke
        // refresh failures (mirroring Dio resolving with the original response
        // and attaching fresh error info in extra).
        final response1 = await future1.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Request hung'),
        );
        expect(response1.statusCode, equals(401));

        // State should be reset - second request should trigger new refresh
        final future2 = fresh.get(Uri.parse('http://example.com/2'));

        // Wait for second refresh to be triggered
        await pumpEventQueue();

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

        final mockClient = _mockClient((request) {
          requestCount++;
          final authHeader = request.headers['authorization'];
          // Mirrors the Dio adapter logic exactly:
          // request 2 with token-1 succeeds; any request with token-2 succeeds.
          if (authHeader == 'bearer token-1.jwt' && requestCount == 2) {
            return http.Response(
              '{"success": true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (authHeader == 'bearer token-2.jwt') {
            return http.Response(
              '{"success": true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error": "Unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
          refreshToken: (_, __) async {
            refreshCallCount++;
            return currentToken = OAuth2Token(
              accessToken: 'token-$refreshCallCount.jwt',
              refreshToken: 'refreshToken',
            );
          },
          httpClient: mockClient,
        );

        await fresh.setToken(currentToken);

        // First request - gets 401, triggers first refresh, retry succeeds
        final response1 = await fresh.get(Uri.parse('http://example.com/1'));
        expect(response1.statusCode, equals(200));
        expect(refreshCallCount, equals(1));

        // Wait a bit between requests
        await pumpEventQueue();

        // Second request - gets 401, triggers second refresh, retry succeeds
        final response2 = await fresh.get(Uri.parse('http://example.com/2'));
        expect(response2.statusCode, equals(200));
        expect(refreshCallCount, equals(2));
      },
    );
  });
}

/// Builds a synchronous [http.Client] backed by [handler].
/// Using [MockClient] from package:http/testing.dart keeps the mock
/// setup as close as possible to the Dio _MockAdapter pattern.
http.Client _mockClient(
  http.Response Function(http.Request request) handler,
) {
  return MockClient((request) async => handler(request));
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
  Future<T?> read() async => _token;

  @override
  Future<void> write(T token) async => _token = token;
}
