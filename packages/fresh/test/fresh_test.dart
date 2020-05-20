import 'package:fresh/fresh.dart';
import 'package:test/test.dart';

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
}
