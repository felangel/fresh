import 'package:fresh/fresh.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockToken extends Mock implements OAuth2Token {}

class FakeOAuth2Token extends Fake implements OAuth2Token {}

class MockTokenStorage<OAuth2Token> extends Mock
    implements TokenStorage<OAuth2Token> {}

class FreshController<T> with FreshMixin<T> {
  FreshController(TokenStorage<T> tokenStorage) {
    this.tokenStorage = tokenStorage;
  }
}

void main() {
  group('OAuth2Token', () {
    test('tokenType defaults to bearer', () {
      expect(const OAuth2Token(accessToken: 'accessToken').tokenType, 'bearer');
    });
  });

  group('InMemoryStorage', () {
    late InMemoryTokenStorage<MockToken> inMemoryTokenStorage;
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

  group('FreshMixin', () {
    late TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage();
    });

    group('token', () {
      test('returns token once it has successfully loaded from storage',
          () async {
        final mockToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => mockToken);
        final freshController = FreshController<OAuth2Token>(tokenStorage);
        final token = await freshController.token;
        expect(token, mockToken);
      });
    });

    group('revokeToken', () {
      test('add unauthenticated when call revokeToken', () async {
        final mockToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => mockToken);
        when(() => tokenStorage.delete()).thenAnswer((_) async {});

        final freshController = FreshController<OAuth2Token>(tokenStorage);

        await freshController.revokeToken();

        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );

        verify(() => tokenStorage.delete()).called(1);
        verify(() => tokenStorage.read()).called(1);
      });
    });

    group('initial authentication status', () {
      test('is unauthenticated when tokenStorage.read is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });

      test('is authenticated when tokenStorage.read is not null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );
      });
    });

    group('configureToken', () {
      setUpAll(() {
        registerFallbackValue(FakeOAuth2Token());
      });

      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          final token = MockToken();
          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});
          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.setToken(null);
          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
        test('adds authenticated status if token is not null', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => null);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          final freshController = FreshController<OAuth2Token>(tokenStorage);

          await freshController.setToken(MockToken());

          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder(
              const <AuthenticationStatus>[AuthenticationStatus.authenticated],
            ),
          );
        });
      });

      group('clearToken', () {
        test('adds unauthenticated status when call clearToken()', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});
          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.clearToken();
          await expectLater(
            freshController.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
    });

    group('close', () {
      test('shoud close streams', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final freshController = FreshController<OAuth2Token>(tokenStorage);

        final mockToken = MockToken();
        await freshController.setToken(mockToken);
        await freshController.close();

        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder(
            <Matcher>[equals(AuthenticationStatus.authenticated), emitsDone],
          ),
        );
      });
    });
  });
}
