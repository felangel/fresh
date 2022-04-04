import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_example/splash/splash_page.dart';

void main() {
  group('SplashPage', () {
    testWidgets('should render "Splash Page"', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SplashPage()));
      expect(find.text('Splash Page'), findsOneWidget);
    });
  });
}
