import 'dart:async';

import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockToken extends Mock implements OAuth2Token {
  @override
  String get accessToken => 'accessToken';
}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class FakeUri extends Fake implements Uri {}

Future<OAuth2Token> emptyRefreshToken(OAuth2Token? _, http.Client __) async {
  return MockToken();
}

void main() {
  group('Fresh', () {
    late TokenStorage<OAuth2Token> tokenStorage;

    setUpAll(() {
      registerFallbackValue(MockToken());
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(FakeUri());
    });

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          final token = MockToken();

          when(() => tokenStorage.read()).thenAnswer((_) async => token);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});

          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );

          await fresh.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});

          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );

          await fresh.setToken(null);
          await expectLater(
            fresh.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });

      group('clearToken', () {
        test('adds unauthenticated status when call clearToken()', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});

          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );

          await fresh.clearToken();
          await expectLater(
            fresh.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
    });

    group('shouldRefreshBeforeRequest', () {
      test('does not refresh when token has no expireDate', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final fresh = Fresh.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (token, client) async {
            refreshCallCount++;
            return token ?? MockToken();
          },
        );

        // A GET to a placeholder URL exercises onRequest logic via send().
        final mockClient = _noopClient();
        await _sendGetThrough(fresh, mockClient);

        expect(refreshCallCount, 0);
      });

      test('does not refresh when token is not expired', () async {
        final token = OAuth2Token(
          accessToken: 'accessToken',
          issuedAt: DateTime.now(),
          expiresIn: 3600,
        );
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final fresh = Fresh.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (token, client) async {
            refreshCallCount++;
            return token ?? MockToken();
          },
        );

        await _sendGetThrough(fresh, _noopClient());

        expect(refreshCallCount, 0);
      });

      test('refreshes token when expired', () async {
        final expiredToken = OAuth2Token(
          accessToken: 'expiredToken',
          issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
          expiresIn: 3600,
        );
        const newToken = OAuth2Token(accessToken: 'newToken');

        when(() => tokenStorage.read()).thenAnswer((_) async => expiredToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final fresh = Fresh.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (token, client) async {
            refreshCallCount++;
            return newToken;
          },
          // Use a retry client that always returns 200 so the request
          // completes after the proactive refresh.
          httpClient: _alwaysOkClient(),
        );

        await _sendGetThrough(fresh, _alwaysOkClient());

        expect(refreshCallCount, 1);
        verify(() => tokenStorage.write(any())).called(1);
      });

      test('uses custom shouldRefreshBeforeRequest when provided', () async {
        var customCallCount = 0;
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final fresh = Fresh<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (token) =>
              {'authorization': '${token.tokenType} ${token.accessToken}'},
          shouldRefreshBeforeRequest: (request, token) {
            customCallCount++;
            return false;
          },
        );

        await _sendGetThrough(fresh, _noopClient());

        expect(customCallCount, 1);
      });

      test('calls revokeToken when refresh throws RevokeTokenException',
          () async {
        final expiredToken = OAuth2Token(
          accessToken: 'expiredToken',
          issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
          expiresIn: 3600,
        );

        when(() => tokenStorage.read()).thenAnswer((_) async => expiredToken);
        when(() => tokenStorage.delete()).thenAnswer((_) async {});

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (token, client) async => throw RevokeTokenException(),
        );

        // The send() will catch the RevokeTokenException from the proactive
        // refresh and clear the token; the request itself still completes
        // (no auth header, original response returned).
        await _sendGetThrough(fresh, _noopClient());

        verify(() => tokenStorage.delete()).called(1);
      });

      test('passes BaseRequest to shouldRefreshBeforeRequest', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? capturedRequest;
        final fresh = Fresh<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (token) =>
              {'authorization': '${token.tokenType} ${token.accessToken}'},
          shouldRefreshBeforeRequest: (request, token) {
            capturedRequest = request;
            return false;
          },
        );

        final request = http.Request(
          'GET',
          Uri.parse('https://example.com/api/test'),
        );
        await fresh.send(request);

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.url.path, '/api/test');
        expect(capturedRequest!.method, 'GET');
      });

      test('appends token header to StreamedRequest in-place', () async {
        const oAuth2Token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((request) {
          captured = request;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        final streamed = http.StreamedRequest(
          'POST',
          Uri.parse('https://example.com/upload'),
        );
        // StreamedRequest requires the body stream to be closed or the inner
        // client will wait forever for bytes before returning a response.
        unawaited(streamed.sink.close());

        await fresh.send(streamed);

        expect(captured, same(streamed)); // returned in-place, not a copy
        expect(captured?.headers['authorization'], 'bearer accessToken');
      });

      test('can refresh based on request path', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final fresh = Fresh<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (token, client) async {
            refreshCallCount++;
            return const OAuth2Token(accessToken: 'refreshedToken');
          },
          tokenHeader: (token) => {
            'authorization': '${token.tokenType} ${token.accessToken}',
          },
          shouldRefreshBeforeRequest: (request, token) {
            return request.url.path.contains('/sensitive');
          },
          httpClient: _alwaysOkClient(),
        );

        // Non-sensitive path should not trigger refresh.
        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/api/public')),
        );
        expect(refreshCallCount, 0);

        // Sensitive path should trigger refresh.
        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/api/sensitive')),
        );
        expect(refreshCallCount, 1);
        verify(() => tokenStorage.write(any())).called(1);
      });
    });

    group('send (onRequest equivalent)', () {
      const oAuth2Token = OAuth2Token(accessToken: 'accessToken');

      test(
          'appends default OAuth2 authorization header when '
          'tokenHeader is not provided', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((req) {
          captured = req;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/test')),
        );

        expect(
          captured?.headers['authorization'],
          'bearer accessToken',
        );
      });

      test('appends custom tokenHeader when provided', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((req) {
          captured = req;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (_) => {'custom-header': 'custom-token'},
          httpClient: spyClient,
        );

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/test')),
        );

        expect(captured?.headers['custom-header'], 'custom-token');
        expect(captured?.headers.containsKey('authorization'), isFalse);
      });

      test('does not append token header when isTokenRequired returns false',
          () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((req) {
          captured = req;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          isTokenRequired: (_) => false,
          httpClient: spyClient,
        );

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/test')),
        );

        expect(captured?.headers.containsKey('authorization'), isFalse);
      });

      test('appends token header when isTokenRequired returns true', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((req) {
          captured = req;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          isTokenRequired: (_) => true,
          httpClient: spyClient,
        );

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/test')),
        );

        expect(captured?.headers['authorization'], 'bearer accessToken');
      });

      test('appends token header when isTokenRequired is not provided',
          () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        http.BaseRequest? captured;
        final spyClient = _SpyClient((req) {
          captured = req;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/test')),
        );

        expect(captured?.headers['authorization'], 'bearer accessToken');
      });
    });

    group('send (onResponse equivalent)', () {
      test('returns untouched response when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final spyClient = _SpyClient((_) => http.Response('{}', 200));

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 200);
        // Refresh must not have been attempted.
        verifyNever(() => tokenStorage.write(any()));
      });

      test(
          'returns untouched response when '
          'shouldRefresh (default) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((_) {
          requestCount++;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 200);
        // Only the original request — no retry.
        expect(requestCount, 1);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (custom) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((_) {
          requestCount++;
          return http.Response('{}', 401);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          shouldRefresh: (_) => false,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 401);
        expect(requestCount, 1);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((request) {
          requestCount++;
          // First call → 401; retry (with new token) → 200.
          if (requestCount == 1) return http.Response('{}', 401);
          return http.Response('{"success": true}', 200);
        });

        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {'custom-name': 'custom-value'},
          httpClient: spyClient,
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        final response =
            await fresh.get(Uri.parse('https://example.com/mock/path'));
        expect(response.statusCode, 200);
        expect(refreshCallCount, 1);
        expect(requestCount, 2);
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'wipes tokenStorage and sets authenticationStatus to unauthenticated '
          'when RevokeTokenException is thrown', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        when(tokenStorage.delete).thenAnswer((_) async {});

        final spyClient = _SpyClient((_) => http.Response('{}', 401));

        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            throw RevokeTokenException();
          },
          tokenHeader: (_) => {},
          httpClient: spyClient,
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        // send() throws http.ClientException on RevokeTokenException.
        await expectLater(
          fresh.get(Uri.parse('https://example.com')),
          throwsA(isA<http.ClientException>()),
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );

        expect(refreshCallCount, 1);
        verify(tokenStorage.delete).called(1);
      });

      test('returns same response when shouldRefresh returns false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        await expectLater(
          Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
            httpClient: _SpyClient((_) => http.Response('{}', 200)),
          ).authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        var requestCount = 0;
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: _SpyClient((_) {
            requestCount++;
            return http.Response('{}', 200);
          }),
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 200);
        expect(requestCount, 1);
      });
    });

    // The Dio version has separate onError tests. In package:http, both the
    // response-trigger path and the exception path are unified inside send().
    // These tests verify the same behaviours through send().
    group('send (onError equivalent)', () {
      test('skips refresh when isTokenRequired returns false', () async {
        final mockToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => mockToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshTokenCallCount = 0;
        var requestCount = 0;
        final spyClient = _SpyClient((_) {
          requestCount++;
          return http.Response('{}', 401);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return mockToken;
          },
          shouldRefresh: (_) => true,
          isTokenRequired: (_) => false,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        // Response passes through unchanged; no retry.
        expect(response.statusCode, 401);
        expect(refreshTokenCallCount, 0);
        expect(requestCount, 1);
      });

      test('returns response without refresh when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((_) {
          requestCount++;
          return http.Response('{}', 401);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 401);
        expect(requestCount, 1);
      });

      test(
          'throws http.ClientException when RevokeTokenException is thrown '
          'during retry', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        when(() => tokenStorage.delete()).thenAnswer((_) async {});

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          shouldRefresh: (_) => true,
          refreshToken: (_, __) => throw RevokeTokenException(),
          httpClient: _SpyClient((_) => http.Response('{}', 401)),
        );

        await expectLater(
          fresh.get(Uri.parse('https://example.com')),
          throwsA(isA<http.ClientException>()),
        );
      });

      test('returns response when shouldRefresh (default) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((_) {
          requestCount++;
          return http.Response('{}', 200);
        });

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          httpClient: spyClient,
        );

        final response = await fresh.get(Uri.parse('https://example.com'));
        expect(response.statusCode, 200);
        expect(requestCount, 1);
      });

      test(
          'invokes refreshToken and retries when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        http.BaseRequest? retryRequest;
        final spyClient = _SpyClient((request) {
          requestCount++;
          if (requestCount == 1) return http.Response('{}', 401);
          retryRequest = request;
          return http.Response('{"success": true}', 200);
        });

        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {'custom-name': 'custom-value'},
          httpClient: spyClient,
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        final response =
            await fresh.get(Uri.parse('https://example.com/mock/path'));
        expect(response.statusCode, 200);
        expect(refreshCallCount, 1);
        expect(requestCount, 2);
        expect(retryRequest?.headers['custom-name'], 'custom-value');
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'clones MultipartRequest body when retrying '
          'after token refresh', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        http.BaseRequest? retryRequest;
        final spyClient = _SpyClient((request) {
          requestCount++;
          if (requestCount == 1) return http.Response('{}', 401);
          retryRequest = request;
          return http.Response('{"success": true}', 200);
        });

        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {'custom-name': 'custom-value'},
          httpClient: spyClient,
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        final multipart = http.MultipartRequest(
          'POST',
          Uri.parse('https://example.com/upload'),
        )
          ..fields['key'] = 'value'
          ..files.add(
            http.MultipartFile.fromString('file', 'hello world'),
          );

        final response = await fresh.send(multipart);
        expect(response.statusCode, 200);
        expect(refreshCallCount, 1);
        expect(requestCount, 2);
        // Retry must be a new MultipartRequest (a copy, not the same instance).
        expect(retryRequest, isA<http.MultipartRequest>());
        expect(retryRequest, isNot(same(multipart)));
        expect(
          (retryRequest! as http.MultipartRequest).fields['key'],
          'value',
        );
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'retries plain Request body unchanged after '
          'token refresh', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        http.BaseRequest? retryRequest;
        final spyClient = _SpyClient((request) {
          requestCount++;
          if (requestCount == 1) return http.Response('{}', 401);
          retryRequest = request;
          return http.Response('{"success": true}', 200);
        });

        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {'custom-name': 'custom-value'},
          httpClient: spyClient,
        );

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );

        const body = '{"foo": "bar"}';
        final request = http.Request(
          'POST',
          Uri.parse('https://example.com/mock/path'),
        )..body = body;

        final response = await fresh.send(request);
        expect(response.statusCode, 200);
        expect(refreshCallCount, 1);
        expect(requestCount, 2);
        expect(retryRequest, isA<http.Request>());
        expect((retryRequest! as http.Request).body, body);
        verify(() => tokenStorage.write(token)).called(1);
      });
    });

    group('close', () {
      test('should close streams', () async {
        final token = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.setToken(token);
        await fresh.close();

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(<Matcher>[
            equals(AuthenticationStatus.authenticated),
            emitsDone,
          ]),
        );
      });
    });
  });
}

/// A client that delegates [send] to a synchronous handler and always
/// returns a 200 response for the retry leg (used where we only care about
/// the pre-request refresh, not the retry).
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

/// Returns a client that always responds 200 OK with an empty JSON body.
http.Client _alwaysOkClient() => _SpyClient((_) => http.Response('{}', 200));

/// Returns a client whose response we never inspect (used for pre-request
/// refresh tests where we only care about side-effects before the send).
http.Client _noopClient() => _SpyClient((_) => http.Response('{}', 200));

/// Sends a plain GET through [fresh] using [innerClient] as the httpClient.
/// Convenience wrapper so shouldRefreshBeforeRequest tests don't need to
/// construct Fresh with a separate httpClient every time.
Future<http.Response> _sendGetThrough(
  Fresh<dynamic> fresh,
  http.Client innerClient,
) {
  return fresh.get(Uri.parse('https://example.com/test'));
}
