import 'dart:async';

import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class _MockToken extends Mock implements OAuth2Token {
  @override
  String get accessToken => 'accessToken';
}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class FakeUri extends Fake implements Uri {}

Future<OAuth2Token> emptyRefreshToken(OAuth2Token? _, http.Client __) async {
  return _MockToken();
}

void main() {
  group('Fresh', () {
    late TokenStorage<OAuth2Token> tokenStorage;

    setUpAll(() {
      registerFallbackValue(_MockToken());
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(FakeUri());
    });

    setUp(() {
      tokenStorage = _MockTokenStorage<OAuth2Token>();
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          final token = _MockToken();

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
          when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
          when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
            return token ?? _MockToken();
          },
        );

        await fresh.get(Uri.parse('https://example.com/test'));

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
            return token ?? _MockToken();
          },
        );

        await fresh.get(Uri.parse('https://example.com/test'));

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
          httpClient: _alwaysOkClient(),
        );

        await fresh.get(Uri.parse('https://example.com/test'));

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

        await fresh.get(Uri.parse('https://example.com/test'));

        expect(customCallCount, 1);
      });

      test(
          'calls revokeToken '
          'when refresh throws RevokeTokenException', () async {
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

        await fresh.get(Uri.parse('https://example.com/test'));

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

        await fresh.send(
          http.Request('GET', Uri.parse('https://example.com/api/public')),
        );
        expect(refreshCallCount, 0);

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

        expect(captured?.headers['authorization'], 'bearer accessToken');
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
        verifyNever(() => tokenStorage.write(any()));
      });

      test(
          'returns untouched response when '
          'shouldRefresh (default) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
          'returns untouched response when '
          'shouldRefresh (custom) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
        final token = _MockToken();
        final tokenStorage = _MockTokenStorage<_MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        final spyClient = _SpyClient((request) {
          requestCount++;
          if (requestCount == 1) return http.Response('{}', 401);
          return http.Response('{"success": true}', 200);
        });

        final fresh = Fresh<_MockToken>(
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
          emitsInOrder(
            const <AuthenticationStatus>[AuthenticationStatus.authenticated],
          ),
        );

        final response = await fresh.get(
          Uri.parse('https://example.com/mock/path'),
        );
        expect(response.statusCode, 200);
        expect(refreshCallCount, 1);
        expect(requestCount, 2);
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'wipes tokenStorage and sets authenticationStatus to unauthenticated '
          'when RevokeTokenException is thrown', () async {
        var refreshCallCount = 0;
        final token = _MockToken();
        final tokenStorage = _MockTokenStorage<_MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        when(tokenStorage.delete).thenAnswer((_) async {});

        final spyClient = _SpyClient((_) => http.Response('{}', 401));

        final fresh = Fresh<_MockToken>(
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
        when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
        final mockToken = _MockToken();
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
        when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
        when(() => tokenStorage.read()).thenAnswer((_) async => _MockToken());
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
        final token = _MockToken();
        final tokenStorage = _MockTokenStorage<_MockToken>();
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

        final fresh = Fresh<_MockToken>(
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
        final token = _MockToken();
        final tokenStorage = _MockTokenStorage<_MockToken>();
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

        final fresh = Fresh<_MockToken>(
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
        expect(retryRequest, isA<http.MultipartRequest>());
        expect(retryRequest, isNot(same(multipart)));
        expect(
          (retryRequest! as http.MultipartRequest).fields['key'],
          'value',
        );
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'appends token header to StreamedRequest in-place '
          'and does not retry on 401', () async {
        const oAuth2Token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var requestCount = 0;
        http.BaseRequest? captured;
        final spyClient = _SpyClient((request) {
          requestCount++;
          captured = request;
          return http.Response('{}', 401);
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
        unawaited(streamed.sink.close());

        final response = await fresh.send(streamed);

        expect(captured, same(streamed));
        expect(captured?.headers['authorization'], 'bearer accessToken');
        expect(requestCount, equals(1));
        expect(response.statusCode, equals(401));
      });

      test(
          'retries plain Request body unchanged after '
          'token refresh', () async {
        var refreshCallCount = 0;
        final token = _MockToken();
        final tokenStorage = _MockTokenStorage<_MockToken>();
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

        final fresh = Fresh<_MockToken>(
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
        final token = _MockToken();
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
