import 'package:fresh/fresh.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockToken extends Mock implements OAuth2Token {}

class MockTokenStorage<OAuth2Token> extends Mock
    implements TokenStorage<OAuth2Token> {}

void main() {
  group('OAuth2Token', () {
    test('throws AssertionError when accessToken is null', () {
      expect(
        () => OAuth2Token(accessToken: null),
        throwsA(isA<AssertionError>()),
      );
    });

    test('tokenType defaults to bearer', () {
      expect(OAuth2Token(accessToken: 'accessToken').tokenType, 'bearer');
    });
  });

  group('InMemoryStorage', () {
    InMemoryTokenStorage inMemoryTokenStorage;
    final token = MockToken();

    setUp(() {
      inMemoryTokenStorage = InMemoryTokenStorage();
    });

    test('read returns null when there is no token', () async {
      expect(await inMemoryTokenStorage.read(), isNull);
    });

    test('can write and read token when there is a token', () async {
      await inMemoryTokenStorage.write(token);
      expect(await inMemoryTokenStorage.read(), token);
    });

    test('delete does nothing when there is no token', () async {
      expect(inMemoryTokenStorage.delete(), completes);
    });

    test('delete removes token when there is a token', () async {
      await inMemoryTokenStorage.write(token);
      expect(await inMemoryTokenStorage.read(), token);
      await inMemoryTokenStorage.delete();
      expect(await inMemoryTokenStorage.read(), isNull);
    });
  });

  group('FreshController', () {
    TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage();
    });

    group('revokeToken', () {
      test('add unauthenticated when call revokeToken', () async {
        var mockToken = MockToken();
        when(tokenStorage.read()).thenAnswer((_) async => mockToken);
        when(tokenStorage.delete()).thenAnswer((_) async => null);

        final freshController = FreshController<OAuth2Token>(
          tokenStorage: tokenStorage,
        );

        await freshController.revokeToken();

        expectLater(
          freshController.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );

        verify(tokenStorage.delete()).called(1);
        verify(tokenStorage.read()).called(1);
      });
    });

    group('initial authentication status', () {
      test('is unauthenticated when tokenStorage.read is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        final freshController = FreshController<OAuth2Token>(
          tokenStorage: tokenStorage,
        );
        expectLater(
          freshController.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });

      test('is authenticated when tokenStorage.read is not null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        final freshController = FreshController<OAuth2Token>(
          tokenStorage: tokenStorage,
        );
        expectLater(
          freshController.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.authenticated,
          ]),
        );
      });
    });

    group('configureToken', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final token = MockToken();
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );
          await freshController.setToken(token);
          verify(tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );
          await freshController.setToken(null);
          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder([
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
        test('adds authenticated status if token is not null', () async {
          when(tokenStorage.read()).thenAnswer((_) async => null);
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );

          await freshController.setToken(MockToken());

          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder([AuthenticationStatus.authenticated]),
          );
        });
      });

      group('removeToken', () {
        test('adds unauthenticated status when call removeToken()', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );
          await freshController.removeToken();
          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder([
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
      group('add', () {
        test('adds authenticated status if token is not null', () async {
          when(tokenStorage.read()).thenAnswer((_) async => null);
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );

          await freshController.add(MockToken());

          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder([AuthenticationStatus.authenticated]),
          );
        });

        test('adds unauthenticated status when  add(null)', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final freshController = FreshController<OAuth2Token>(
            tokenStorage: tokenStorage,
          );
          await freshController.add(null);
          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder([
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
    });

    group('close', () {
      test('shoud close streams', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final freshController = FreshController<OAuth2Token>(
          tokenStorage: tokenStorage,
        );

        final mockToken = MockToken();
        await freshController.setToken(mockToken);
        await freshController.close();

        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder([AuthenticationStatus.authenticated, emitsDone]),
        );

        await expectLater(
          freshController.currentToken,
          emitsInOrder([mockToken, emitsDone]),
        );
      });
    });
  });
}
