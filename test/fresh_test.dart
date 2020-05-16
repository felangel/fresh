import 'package:fresh/fresh.dart';
import 'package:test/test.dart';

void main() {
  group('Fresh', () {
    test('throws AssertionError when tokenStorage is null', () {
      expect(
        () => Fresh(tokenStorage: null, refreshToken: (_, __) async {}),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
