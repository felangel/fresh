import 'package:fresh/fresh.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  group('Fresh', () {
    TokenStorage tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage();
    });

    test('throws AssertionError when tokenStorage is null', () {
      expect(
        () => Fresh(tokenStorage: null, refreshToken: (_, __) async {}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when refreshToken is null', () {
      expect(
        () => Fresh(tokenStorage: tokenStorage, refreshToken: null),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
