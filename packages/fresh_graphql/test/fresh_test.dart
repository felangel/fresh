import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockOAuth2Token extends Mock implements OAuth2Token {}

class MockToken extends Mock implements OAuth2Token {}

class MockOperation extends Mock implements Operation {}

class MockFetchResult extends Mock implements FetchResult {}

Future<T> emptyRefreshToken<T>(dynamic _, dynamic __) async => null;

void main() {
  group('FreshLink', () {
    TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
    });

    group('constructor', () {
      test('throws AssertionError when tokenStorage is null', () {
        expect(
          () => FreshLink.oAuth2(
            tokenStorage: null,
            refreshToken: (_, __) async => null,
          ),
          throwsA(isA<AssertionError>()),
        );
      });

      test('throws AssertionError when refreshToken is null', () {
        expect(
          () =>
              FreshLink.oAuth2(tokenStorage: tokenStorage, refreshToken: null),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('request', () {
      const token = OAuth2Token(accessToken: 'accessToken');

      test(
          'uses cached token and sets default '
          'operation context headers', () async {
        when(tokenStorage.read()).thenAnswer((_) async => token);
        final operation = MockOperation();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {}),
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
        verify(operation.setContext(<String, dynamic>{
          'headers': {'authorization': 'bearer accessToken'}
        })).called(1);
        verify(tokenStorage.read()).called(1);
      });

      test(
          'uses cached token and sets custom '
          'operation context headers', () async {
        when(tokenStorage.read()).thenAnswer((_) async => token);
        final operation = MockOperation();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
          tokenHeader: (token) =>
              {'custom_header': 'custom ${token.accessToken}'},
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {}),
          emitsDone,
        );
        verify(operation.setContext(<String, dynamic>{
          'headers': {'custom_header': 'custom accessToken'}
        })).called(1);
        verify(tokenStorage.read()).called(1);
      });

      test(
          'uses cached token and sets empty '
          'operation context headers when token is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        final operation = MockOperation();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {}),
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
        verify(
          operation.setContext(
            <String, dynamic>{'headers': <String, String>{}},
          ),
        ).called(1);
        verify(tokenStorage.read()).called(1);
      });

      test(
          'does not append token when token is not OAuth2 '
          'and tokenHeader is not provided', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        final operation = MockOperation();
        final freshLink = FreshLink<OAuth2Token>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {}),
          emitsDone,
        );
        verify(operation.setContext(
          <String, dynamic>{'headers': <String, String>{}},
        )).called(1);
      });

      test('does not refresh if token is null', () async {
        tokenStorage = MockTokenStorage<Null>();
        when(tokenStorage.read()).thenAnswer((_) async => null);
        var refreshTokenCallCount = 0;
        final operation = MockOperation();
        final fetchResult = MockFetchResult();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return const OAuth2Token(accessToken: 'token');
          },
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder(<MockFetchResult>[fetchResult]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test(
          'does not refresh if statusCode is 200 '
          'using default shouldRefresh', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        var refreshTokenCallCount = 0;
        final operation = MockOperation();
        final fetchResult = MockFetchResult();
        when(fetchResult.statusCode).thenReturn(200);
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return null;
          },
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder(<MockFetchResult>[fetchResult]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test(
          'does not refresh if statusCode is 401 '
          'using custom shouldRefresh', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        var refreshTokenCallCount = 0;
        final operation = MockOperation();
        final fetchResult = MockFetchResult();
        when(fetchResult.statusCode).thenReturn(401);
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return null;
          },
          shouldRefresh: (_) => false,
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder(<MockFetchResult>[fetchResult]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test(
          'does refresh if statusCode is 401 '
          'using default shouldRefresh', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        const refreshedToken = OAuth2Token(accessToken: 'newAccessToken');
        when(tokenStorage.read()).thenAnswer((_) async => token);
        var refreshTokenCallCount = 0;
        final operation = MockOperation();
        final fetchResult = MockFetchResult();
        when(fetchResult.statusCode).thenReturn(401);
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            return refreshedToken;
          },
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder(<MockFetchResult>[fetchResult]),
        );
        expect(refreshTokenCallCount, 1);
        verify(operation.setContext(<String, dynamic>{
          'headers': {'authorization': 'bearer newAccessToken'}
        })).called(1);
      });

      test(
          'calls tokenStorage.delete '
          'when RevokeTokenException is thrown', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        var refreshTokenCallCount = 0;
        final operation = MockOperation();
        final fetchResult = MockFetchResult();
        when(fetchResult.statusCode).thenReturn(401);
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshTokenCallCount++;
            throw RevokeTokenException();
          },
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder(<MockFetchResult>[fetchResult]),
        );
        expect(refreshTokenCallCount, 1);
        verify(tokenStorage.delete()).called(1);
      });
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write for non-null token', () async {
          when(tokenStorage.read()).thenAnswer((_) async => null);
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final token = MockOAuth2Token();
          final freshLink = FreshLink.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await freshLink.setToken(token);
          verify(tokenStorage.write(token)).called(1);
        });

        test('invokes tokenStorage.delete for null token', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockOAuth2Token());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshLink = FreshLink.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await freshLink.setToken(null);
          verify(tokenStorage.delete()).called(1);
        });
      });

      group('clearToken', () {
        test('invokes tokenStorage.delete', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockOAuth2Token());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshLink = FreshLink.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await freshLink.clearToken();
          verify(tokenStorage.delete()).called(1);
        });
      });
    });

    group('close', () {
      test('should close streams', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        final mockToken = MockToken();
        await fresh.setToken(mockToken);
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
