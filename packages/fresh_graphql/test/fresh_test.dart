// ignore_for_file: must_be_immutable

import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockOAuth2Token extends Mock implements OAuth2Token {}

class MockToken extends Mock implements OAuth2Token {}

class MockRequest extends Mock implements Request {
  final Map<String, String> headers = {};

  @override
  Request updateContextEntry<T extends ContextEntry>(
    ContextUpdater<T?> update,
  ) {
    final result = update.call(null);
    if (result is HttpLinkHeaders) {
      headers.addAll(result.headers);
    }
    return this;
  }
}

class MockResponse extends Mock implements Response {}

Future<T?> emptyRefreshToken<T>(dynamic _, dynamic __) async => null;

void main() {
  setUpAll(() {
    registerFallbackValue(MockToken());
  });

  group('FreshLink', () {
    late TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
    });

    group('shouldRefreshBeforeRequest', () {
      test('does not refresh when token has no expireDate', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);

        var refreshCallCount = 0;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return const OAuth2Token(accessToken: 'newToken');
          },
          shouldRefresh: (_) => false,
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

        expect(refreshCallCount, 0);
      });

      test('does not refresh when token is not expired', () async {
        final token = OAuth2Token(
          accessToken: 'accessToken',
          issuedAt: DateTime.now(),
          expiresIn: 3600, // 1 hour
        );
        when(() => tokenStorage.read()).thenAnswer((_) async => token);

        var refreshCallCount = 0;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return const OAuth2Token(accessToken: 'newToken');
          },
          shouldRefresh: (_) => false,
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

        expect(refreshCallCount, 0);
      });

      test('refreshes token when expired', () async {
        final expiredToken = OAuth2Token(
          accessToken: 'expiredToken',
          issuedAt: DateTime.now().subtract(const Duration(hours: 2)),
          expiresIn: 3600, // 1 hour
        );
        const newToken = OAuth2Token(accessToken: 'newToken');

        when(() => tokenStorage.read()).thenAnswer((_) async => expiredToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return newToken;
          },
          shouldRefresh: (_) => false,
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

        expect(refreshCallCount, 1);
        verify(() => tokenStorage.write(any())).called(1);
      });

      test('uses custom shouldRefreshBeforeRequest when provided', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);

        var customCallCount = 0;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => token,
          shouldRefresh: (_) => false,
          shouldRefreshBeforeRequest: (request, token) {
            customCallCount++;
            return false;
          },
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

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

        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            throw RevokeTokenException();
          },
          shouldRefresh: (_) => false,
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

        verify(() => tokenStorage.delete()).called(1);
      });

      test('passes Request to shouldRefreshBeforeRequest', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);

        Request? capturedRequest;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => token,
          shouldRefresh: (_) => false,
          shouldRefreshBeforeRequest: (request, token) {
            capturedRequest = request;
            return false;
          },
        );

        final request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );

        expect(capturedRequest, isNotNull);
        expect(capturedRequest, equals(request));
      });

      test('can refresh based on request data', () async {
        const token = OAuth2Token(accessToken: 'accessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        var refreshCallCount = 0;
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return const OAuth2Token(accessToken: 'refreshedToken');
          },
          shouldRefresh: (_) => false,
          shouldRefreshBeforeRequest: (request, token) {
            // Check if request is a mock with headers
            if (request is MockRequest) {
              return request.headers.isNotEmpty;
            }
            return false;
          },
        );

        // Request without headers should not trigger refresh
        var request = MockRequest();
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );
        expect(refreshCallCount, 0);

        // Request with headers should trigger refresh
        request = MockRequest();
        request.headers['operation'] = 'sensitiveOperation';
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );
        expect(refreshCallCount, 1);
        verify(() => tokenStorage.write(any())).called(1);
      });
    });

    group('request', () {
      const token = OAuth2Token(accessToken: 'accessToken');

      test(
          'uses cached token and sets default '
          'request context headers', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        final request = MockRequest();
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
          shouldRefresh: (_) => false,
        );
        late MockRequest updatedRequest;
        await expectLater(
          freshLink.request(request, (operation) async* {
            updatedRequest = operation as MockRequest;
          }),
          emitsDone,
        );
        await expectLater(
          freshLink.authenticationStatus,
          emitsInOrder(
            const <AuthenticationStatus>[
              AuthenticationStatus.authenticated,
            ],
          ),
        );
        expect(request.headers, {'authorization': 'bearer accessToken'});
        expect(updatedRequest.headers, {'authorization': 'bearer accessToken'});
        verify(() => tokenStorage.read()).called(1);
      });

      test(
          'uses cached token and sets custom '
          'operation context headers', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        final request = MockRequest();
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
          shouldRefresh: (_) => false,
          tokenHeader: (token) =>
              {'custom_header': 'custom ${token?.accessToken}'},
        );
        late MockRequest updatedRequest;
        await expectLater(
          freshLink.request(request, (operation) async* {
            updatedRequest = operation as MockRequest;
          }),
          emitsDone,
        );
        expect(request.headers, {'custom_header': 'custom accessToken'});
        expect(updatedRequest.headers, {'custom_header': 'custom accessToken'});
        verify(() => tokenStorage.read()).called(1);
      });

      test(
          'uses cached token and sets empty '
          'operation context headers when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        final request = MockRequest();
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
          shouldRefresh: (_) => false,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );
        await expectLater(
          freshLink.authenticationStatus,
          emitsInOrder(
            const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ],
          ),
        );
        expect(request.headers, <String, String>{});
        verify(() => tokenStorage.read()).called(1);
      });

      test(
          'does not append token when token is not OAuth2 '
          'and tokenHeader is not provided', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        final request = MockRequest();
        final freshLink = FreshLink<OAuth2Token>(
          shouldRefresh: (_) => false,
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {}),
          emitsDone,
        );
        expect(request.headers, <String, String>{});
      });

      test('does not refresh if token is null', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        var refreshTokenCallCount = 0;
        final request = MockRequest();
        final response = MockResponse();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return const OAuth2Token(accessToken: 'token');
          },
          shouldRefresh: (_) => false,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {
            yield response;
          }),
          emitsInOrder(<MockResponse>[response]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test('does not refresh if error occurs and shouldRefresh returns false ',
          () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        var refreshTokenCallCount = 0;
        final request = MockRequest();
        final response = MockResponse();
        when(() => response.errors)
            .thenReturn([const GraphQLError(message: 'oops')]);
        final freshLink = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return null;
          },
          shouldRefresh: (_) => false,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {
            yield response;
          }),
          emitsInOrder(<MockResponse>[response]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test(
          'does refresh if error occurs and shouldRefresh returns true '
          'using default shouldRefresh', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        const refreshedToken = OAuth2Token(accessToken: 'newAccessToken');
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        var refreshTokenCallCount = 0;
        final request = MockRequest();
        final response = MockResponse();
        when(() => response.errors)
            .thenReturn([const GraphQLError(message: 'oops')]);
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return refreshedToken;
          },
          shouldRefresh: (_) => true,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {
            yield response;
          }),
          emitsInOrder(<MockResponse>[response]),
        );
        expect(refreshTokenCallCount, 1);
        expect(request.headers, {'authorization': 'bearer newAccessToken'});
      });

      test(
          'calls tokenStorage.delete '
          'when RevokeTokenException is thrown', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(() => tokenStorage.read()).thenAnswer((_) async => token);
        when(() => tokenStorage.delete()).thenAnswer((_) async {});
        var refreshTokenCallCount = 0;
        final request = MockRequest();
        final response = MockResponse();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            throw RevokeTokenException();
          },
          shouldRefresh: (_) => true,
        );
        await expectLater(
          freshLink.request(request, (operation) async* {
            yield response;
          }),
          emitsInOrder(<MockResponse>[response]),
        );
        expect(refreshTokenCallCount, 1);
        verify(() => tokenStorage.delete()).called(1);
      });
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write for non-null token', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => null);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          final token = MockOAuth2Token();

          final freshLink = FreshLink.oAuth2<OAuth2Token>(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
            shouldRefresh: (_) => false,
          );
          await freshLink.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('invokes tokenStorage.delete for null token', () async {
          when(() => tokenStorage.read())
              .thenAnswer((_) async => MockOAuth2Token());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});
          final freshLink = FreshLink.oAuth2<OAuth2Token>(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
            shouldRefresh: (_) => false,
          );
          await freshLink.setToken(null);
          verify(() => tokenStorage.delete()).called(1);
        });
      });

      group('clearToken', () {
        test('invokes tokenStorage.delete', () async {
          final token = MockOAuth2Token();
          when(() => tokenStorage.read()).thenAnswer((_) async => token);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});

          final freshLink = FreshLink.oAuth2<OAuth2Token>(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
            shouldRefresh: (_) => false,
          );
          await freshLink.clearToken();
          verify(() => tokenStorage.delete()).called(1);
        });
      });
    });

    group('close', () {
      test('should close streams', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final token = MockOAuth2Token();

        final fresh = FreshLink.oAuth2<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          shouldRefresh: (_) => false,
        );

        await fresh.setToken(token);
        await fresh.close();

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(
            <Matcher>[
              equals(AuthenticationStatus.authenticated),
              emitsDone,
            ],
          ),
        );
      });
    });
  });
}
