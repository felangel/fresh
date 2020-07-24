import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockOAuth2Token extends Mock implements OAuth2Token {}

class MockToken extends Mock implements OAuth2Token {}

class MockOperation extends Mock implements Operation {}

class MockFetchResult extends Mock implements FetchResult {}

Future<T> emptyRefreshToken<T>(_, __) async => null;

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
      final token = OAuth2Token(accessToken: 'accessToken');

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
          emitsInOrder([AuthenticationStatus.authenticated]),
        );
        verify(operation.setContext({
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
        verify(operation.setContext({
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
          emitsInOrder([AuthenticationStatus.unauthenticated]),
        );
        verify(operation.setContext({'headers': {}})).called(1);
        verify(tokenStorage.read()).called(1);
      });

      test(
          'throws UnimplementedError when token is not OAuth2Token '
          'and tokenHeader is not provided', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        final operation = MockOperation();
        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async => null,
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {}),
          emitsError(isA<UnimplementedError>()),
        );
      }, skip: true);

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
            return OAuth2Token(accessToken: 'token');
          },
        );
        await expectLater(
          freshLink.request(operation, (operation) async* {
            yield fetchResult;
          }),
          emitsInOrder([fetchResult]),
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
          emitsInOrder([fetchResult]),
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
          emitsInOrder([fetchResult]),
        );
        expect(refreshTokenCallCount, 0);
      });

      test(
          'does refresh if statusCode is 401 '
          'using default shouldRefresh', () async {
        tokenStorage = MockTokenStorage<OAuth2Token>();
        final refreshedToken = OAuth2Token(accessToken: 'newAccessToken');
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
          emitsInOrder([fetchResult]),
        );
        expect(refreshTokenCallCount, 1);
        verify(operation.setContext({
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
          emitsInOrder([fetchResult]),
        );
        expect(refreshTokenCallCount, 1);
        verify(tokenStorage.delete()).called(1);
      });
    });

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

      group('add', () {
        test('invokes tokenStorage.write for non-null token', () async {
          when(tokenStorage.read()).thenAnswer((_) async => null);
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final token = MockOAuth2Token();
          final freshLink = FreshLink.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await freshLink.add(token);
          verify(tokenStorage.write(token)).called(1);
        });

        test('invokes tokenStorage.delete for null token', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockOAuth2Token());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshLink = FreshLink.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await freshLink.add(null);
          verify(tokenStorage.delete()).called(1);
        });
      });
    });

    group('close', () {
      test('shoud close streams', () async {
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
          emitsInOrder([AuthenticationStatus.authenticated, emitsDone]),
        );

        await expectLater(
          fresh.currentToken,
          emitsInOrder([mockToken, emitsDone]),
        );
      });
    });
  });
}
