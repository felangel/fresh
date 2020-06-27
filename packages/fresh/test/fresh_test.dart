import 'package:fresh/fresh.dart';
import 'package:test/test.dart';

class FakeToken {}

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
    final token = FakeToken();

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
}
