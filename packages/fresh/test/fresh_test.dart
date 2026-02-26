import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockToken extends Mock implements OAuth2Token {
  @override
  String toString() {
    return 'MockToken@${identityHashCode(this).toRadixString(16)}';
  }
}

class FakeOAuth2Token extends Fake implements OAuth2Token {}

class MockTokenStorage<T extends OAuth2Token> extends Mock
    implements TokenStorage<T> {}

class FreshController<T> with FreshMixin<T> {
  FreshController(TokenStorage<T> tokenStorage) {
    this.tokenStorage = tokenStorage;
  }

  Future<T> Function(T? token)? refreshTokenFn;

  @override
  Future<T> performTokenRefresh(T? token) {
    final refreshAction = refreshTokenFn;
    if (refreshAction == null) {
      throw StateError(
        'refreshTokenFn must be set before calling refreshToken',
      );
    }
    return refreshAction(token);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeOAuth2Token());
  });

  group('OAuth2Token', () {
    test('tokenType defaults to bearer', () {
      expect(const OAuth2Token(accessToken: 'accessToken').tokenType, 'bearer');
    });

    group('expiresAt', () {
      test('returns null when issuedAt is null', () {
        const token = OAuth2Token(
          accessToken: 'accessToken',
          expiresIn: 3600,
        );
        expect(token.expiresAt, isNull);
      });

      test('returns null when expiresIn is null', () {
        final issuedAt = DateTime(2023, 1, 1, 12);
        final token = OAuth2Token(
          accessToken: 'accessToken',
          issuedAt: issuedAt,
        );
        expect(token.expiresAt, isNull);
      });

      test('returns null when both issuedAt and expiresIn are null', () {
        const token = OAuth2Token(
          accessToken: 'accessToken',
        );
        expect(token.expiresAt, isNull);
      });

      test('returns correct expiration', () {
        final issuedAt = DateTime(2023, 1, 1, 12);
        final token = OAuth2Token(
          accessToken: 'accessToken',
          expiresIn: 3600,
          issuedAt: issuedAt,
        );
        final expectedExpiration = issuedAt.add(const Duration(seconds: 3600));
        expect(token.expiresAt, equals(expectedExpiration));
      });
    });

    group('toString', () {
      test('includes only non-null fields for minimal token', () {
        const token = OAuth2Token(accessToken: 'myAccessToken123');
        final result = token.toString();

        expect(result, contains('OAuth2Token'));
        expect(result, contains('accessToken: myAc...n123'));
        expect(result, isNot(contains('refreshToken')));
        expect(result, isNot(contains('expiresIn')));
        expect(result, isNot(contains('scope')));
        expect(result, isNot(contains('issuedAt')));
      });

      test('includes all fields when all are provided', () {
        final issuedAt = DateTime(2023, 1, 1, 12);
        final token = OAuth2Token(
          accessToken: 'myAccessToken123',
          refreshToken: 'myRefreshToken456',
          tokenType: 'bearer',
          expiresIn: 3600,
          scope: 'read write',
          issuedAt: issuedAt,
        );
        final result = token.toString();

        expect(result, contains('OAuth2Token'));
        expect(result, contains('accessToken: myAc...n123'));
        expect(result, contains('refreshToken: myRe...n456'));
        expect(result, contains('tokenType: bearer'));
        expect(result, contains('expiresIn: 3600'));
        expect(result, contains('scope: read write'));
        expect(result, contains('issuedAt: 2023-01-01 12:00:00.000'));
        expect(result, contains('expiresAt: 2023-01-01 13:00:00.000'));
      });
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

      test('waits for storage read to complete', () async {
        final mockToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async {
          await Future<void>.delayed(Duration.zero);
          return mockToken;
        });
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
          final token = MockToken();
          when(() => tokenStorage.read()).thenAnswer((_) async => token);
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

          final token = MockToken();
          await freshController.setToken(token);

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
      test('should close streams gracefully', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final token = MockToken();

        final freshController = FreshController<OAuth2Token>(tokenStorage);

        await freshController.setToken(token);
        await freshController.close();
        await freshController.setToken(token);

        await expectLater(
          freshController.authenticationStatus,
          emitsInOrder(
            <Matcher>[equals(AuthenticationStatus.authenticated), emitsDone],
          ),
        );
      });
    });

    group('refreshToken', () {
      setUpAll(() {
        registerFallbackValue(FakeOAuth2Token());
      });

      test('calls refreshAction and returns refreshed token', () async {
        final initialToken = MockToken();
        final refreshedToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => initialToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final freshController = FreshController<OAuth2Token>(tokenStorage);
        // Wait for initial token to load
        await freshController.token;

        freshController.refreshTokenFn = (token) async => refreshedToken;
        final result = await freshController.refreshToken(
          tokenUsedForRequest: initialToken,
        );

        expect(result, refreshedToken);
        verify(() => tokenStorage.write(refreshedToken)).called(1);
      });

      test(
        'returns current token without refreshing '
        'when token already refreshed by another request',
        () async {
          final oldToken = MockToken();
          final currentToken = MockToken();
          when(() => tokenStorage.read()).thenAnswer((_) async => oldToken);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});

          final freshController = FreshController<OAuth2Token>(tokenStorage);
          // Wait for initial token to load
          await freshController.token;

          // Simulate another request having already refreshed the token
          await freshController.setToken(currentToken);

          var refreshActionCalled = false;
          freshController.refreshTokenFn = (token) async {
            refreshActionCalled = true;
            return MockToken();
          };
          final result = await freshController.refreshToken(
            tokenUsedForRequest: oldToken,
          );

          expect(result, currentToken);
          expect(refreshActionCalled, isFalse);
        },
      );

      test('concurrent calls share the same refresh future', () async {
        final initialToken = MockToken();
        final refreshedToken = MockToken();
        var refreshCallCount = 0;
        when(() => tokenStorage.read()).thenAnswer((_) async => initialToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await freshController.token;

        final completer = Completer<OAuth2Token>();
        freshController.refreshTokenFn = (token) {
          refreshCallCount++;
          return completer.future;
        };

        // Start first refresh (will be pending on completer)
        final future1 = freshController.refreshToken(
          tokenUsedForRequest: initialToken,
        );

        // Start second refresh — should join the in-flight future
        final future2 = freshController.refreshToken(
          tokenUsedForRequest: initialToken,
        );

        // Complete the refresh
        completer.complete(refreshedToken);

        final result1 = await future1;
        final result2 = await future2;

        expect(result1, refreshedToken);
        expect(result2, refreshedToken);
        expect(refreshCallCount, 1);
      });

      test('clears token and rethrows on RevokeTokenException', () async {
        final initialToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => initialToken);
        when(() => tokenStorage.delete()).thenAnswer((_) async {});

        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await freshController.token;
        freshController.refreshTokenFn =
            (token) async => throw RevokeTokenException();

        await expectLater(
          () => freshController.refreshToken(tokenUsedForRequest: initialToken),
          throwsA(isA<RevokeTokenException>()),
        );

        verify(() => tokenStorage.delete()).called(1);
        expect(await freshController.token, isNull);
      });

      test('rethrows generic exception without clearing token', () async {
        final initialToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => initialToken);

        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await freshController.token;
        freshController.refreshTokenFn =
            (token) async => throw Exception('network error');

        await expectLater(
          () => freshController.refreshToken(tokenUsedForRequest: initialToken),
          throwsA(isA<Exception>()),
        );

        // Token should still be there
        expect(await freshController.token, initialToken);
      });

      test('clears in-flight future after exception, allowing new refresh',
          () async {
        final initialToken = MockToken();
        final refreshedToken = MockToken();
        when(() => tokenStorage.read()).thenAnswer((_) async => initialToken);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});

        final freshController = FreshController<OAuth2Token>(tokenStorage);
        await freshController.token;

        var shouldFail = true;
        freshController.refreshTokenFn = (token) async {
          if (shouldFail) throw Exception('network error');
          return refreshedToken;
        };

        // First call fails
        await expectLater(
          () => freshController.refreshToken(tokenUsedForRequest: initialToken),
          throwsA(isA<Exception>()),
        );

        // Second call should start a new refresh, not be stuck
        shouldFail = false;
        final result = await freshController.refreshToken(
          tokenUsedForRequest: initialToken,
        );

        expect(result, refreshedToken);
      });

      test(
        'skips refresh when tokenUsedForRequest is null '
        'but token was already refreshed by another request',
        () async {
          // Start with no token
          when(() => tokenStorage.read()).thenAnswer((_) async => null);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});

          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.token;

          // Another request refreshes the token in the meantime
          final newToken = MockToken();
          await freshController.setToken(newToken);

          // Our request was made with null token, now tries to refresh
          var refreshCalled = false;
          freshController.refreshTokenFn = (token) async {
            refreshCalled = true;
            return MockToken();
          };

          final result = await freshController.refreshToken(
            tokenUsedForRequest: null,
          );

          // Should return the already-refreshed token
          expect(result, newToken);
          expect(refreshCalled, isFalse);
        },
      );

      test(
        'returns current token when tokenUsedForRequest differs '
        'and current token is not null',
        () async {
          final oldToken = MockToken();
          final currentToken = MockToken();
          when(() => tokenStorage.read()).thenAnswer((_) async => oldToken);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});

          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.token;
          await freshController.setToken(currentToken);

          freshController.refreshTokenFn = (token) async => MockToken();

          final result = await freshController.refreshToken(
            tokenUsedForRequest: oldToken,
          );

          expect(result, currentToken);
        },
      );
    });

    group('initial storage read', () {
      setUpAll(() {
        registerFallbackValue(FakeOAuth2Token());
      });

      test(
        'initial read does not overwrite explicit setToken',
        () async {
          final storedToken = MockToken();
          final newToken = MockToken();

          // Slow storage read to simulate async persistence
          final readCompleter = Completer<OAuth2Token?>();
          when(() => tokenStorage.read())
              .thenAnswer((_) => readCompleter.future);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});

          final freshController = FreshController<OAuth2Token>(tokenStorage);

          // Set token before the initial read completes
          await freshController.setToken(newToken);

          // Now complete the initial read with the old stored token
          readCompleter.complete(storedToken);
          await pumpEventQueue();

          // The explicitly set token must win
          final token = await freshController.token;
          expect(
            token,
            newToken,
            reason: 'initial storage read should not overwrite '
                'an explicit setToken call',
          );
        },
      );

      test(
        'initial read does not overwrite explicit clearToken',
        () async {
          final storedToken = MockToken();

          final readCompleter = Completer<OAuth2Token?>();
          when(() => tokenStorage.read())
              .thenAnswer((_) => readCompleter.future);
          when(() => tokenStorage.delete()).thenAnswer((_) async {});

          final freshController = FreshController<OAuth2Token>(tokenStorage);

          // Clear token before the initial read completes
          await freshController.clearToken();

          // Now complete the initial read with a stored token
          readCompleter.complete(storedToken);
          await pumpEventQueue();

          // The explicit clear must win
          final token = await freshController.token;
          expect(
            token,
            isNull,
            reason: 'initial storage read should not overwrite '
                'an explicit clearToken call',
          );
        },
      );
    });

    // https://github.com/felangel/fresh/issues/115
    group('race condition: token getter during setToken', () {
      setUpAll(() {
        registerFallbackValue(FakeOAuth2Token());
      });

      test(
        'token getter returns new token while setToken is writing to storage',
        () async {
          final oldToken = MockToken();
          final newToken = MockToken();

          // Storage with a delayed write to simulate async persistence
          final writeCompleter = Completer<void>();
          when(() => tokenStorage.read()).thenAnswer((_) async => oldToken);
          when(() => tokenStorage.write(any())).thenAnswer((_) async {
            await writeCompleter.future;
          });

          final freshController = FreshController<OAuth2Token>(tokenStorage);
          // Wait for initial token load
          await freshController.token;

          // Start setToken but don't await it
          final setTokenFuture = freshController.setToken(newToken);

          // While storage write is in progress, read the token
          final tokenDuringWrite = await freshController.token;

          // Complete the storage write
          writeCompleter.complete();
          await setTokenFuture;

          final tokenAfterWrite = await freshController.token;

          // The token getter should return the new token even during write
          expect(
            tokenDuringWrite,
            newToken,
            reason: 'token getter should return newToken during setToken, '
                'not the stale oldToken',
          );
          expect(tokenAfterWrite, newToken);
        },
      );

      test(
        'token getter returns null while clearToken is deleting from storage',
        () async {
          final oldToken = MockToken();

          final deleteCompleter = Completer<void>();
          when(() => tokenStorage.read()).thenAnswer((_) async => oldToken);
          when(() => tokenStorage.delete()).thenAnswer((_) async {
            await deleteCompleter.future;
          });

          final freshController = FreshController<OAuth2Token>(tokenStorage);
          await freshController.token;

          // Start clearToken but don't await it
          final clearTokenFuture = freshController.clearToken();

          // While storage delete is in progress, read the token
          final tokenDuringDelete = await freshController.token;

          // Complete the storage delete
          deleteCompleter.complete();
          await clearTokenFuture;

          final tokenAfterDelete = await freshController.token;

          // The token getter should reflect the cleared state
          expect(
            tokenDuringDelete,
            isNull,
            reason: 'token getter should return null during clearToken, '
                'not the stale oldToken',
          );
          expect(tokenAfterDelete, isNull);
        },
      );
    });
  });
}
