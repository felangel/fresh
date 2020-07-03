import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockTokenStorage<OoAuth2Token> extends Mock
    implements TokenStorage<OoAuth2Token> {}

class MockToken extends Mock implements OAuth2Token {}

class MockRequestOptions extends Mock implements RequestOptions {}

class MockResponse extends Mock implements Response {}

class MockDioError extends Mock implements DioError {}

class MockHttpClient extends Mock implements Dio {}

Future<T> emptyRefreshToken<T>(_, __) async => null;

void main() {
  group('Fresh', () {
    TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage();
    });

    test('throws AssertionError when tokenStorage is null', () {
      expect(
        () => Fresh.oAuth2Token(
            tokenStorage: null, refreshToken: emptyRefreshToken),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when refreshToken is null', () {
      expect(
        () => Fresh.oAuth2Token(
            tokenStorage: null, refreshToken: emptyRefreshToken),
        throwsA(isA<AssertionError>()),
      );
    });

    group('initial authentication status', () {
      test('is unauthenticated when tokenStorage.read is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });

      test('is authenticated when tokenStorage.read is not null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.authenticated,
          ]),
        );
      });
    });

    group('setToken', () {
      test('invokes tokenStorage.write', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final token = MockToken();
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await fresh.setToken(token);
        verify(tokenStorage.write(token)).called(1);
      });

      test('adds unauthenticated status when call removeToken()', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await fresh.removeToken();
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });

      test('adds unauthenticated status when call setToken(null)', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await fresh.setToken(null);
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );
      });

      test('adds authenticated status if token is not null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.setToken(MockToken());

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([AuthenticationStatus.authenticated]),
        );
      });
    });

    group('onRequest', () {
      final ooAuth2Token = OAuth2Token(accessToken: 'accessToken');
      test(
          'appends token header when token is OoAuth2Token '
          'and tokenHeader is not provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => ooAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onRequest(options) as RequestOptions;
        expect(
          actual.headers,
          {
            'content-type': null,
            'authorization': 'bearer accessToken',
          },
        );
      });

      test(
          'appends token header when token is OoAuth2Token '
          'and tokenHeader is provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => ooAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (_) => {'custom-header': 'custom-token'},
        );
        final actual = await fresh.onRequest(options) as RequestOptions;
        expect(
          actual.headers,
          {
            'content-type': null,
            'custom-header': 'custom-token',
          },
        );
      });

      test(
          'appends the standart header when token use OoAuth2Token constructor'
          'but tokenHeader is not provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => ooAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onRequest(options) as RequestOptions;
        expect(
          actual.headers,
          {
            'content-type': null,
            'authorization':
                '${ooAuth2Token.tokenType} ${ooAuth2Token.accessToken}',
          },
        );
      });

      test('throws AssertionError when tokenHeader is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);

        expect(
          () {
            Fresh(
              tokenHeader: null,
              tokenStorage: tokenStorage,
              refreshToken: emptyRefreshToken,
            );
          },
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('onResponse', () {
      test('returns untouched response when token is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final response = MockResponse();
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onResponse(response);
        expect(actual, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (default) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final response = MockResponse();
        when(response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onResponse(response);
        expect(actual, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (custom) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final response = MockResponse();
        when(response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          shouldRefresh: (_) => false,
        );
        final actual = await fresh.onResponse(response);
        expect(actual, response);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final request = MockRequestOptions();
        when(request.path).thenReturn('/mock/path');
        when(request.headers).thenReturn({});
        final response = MockResponse();
        when(response.statusCode).thenReturn(401);
        when(response.request).thenReturn(request);
        final httpClient = MockHttpClient();
        when(httpClient.request(
          any,
          cancelToken: anyNamed('cancelToken'),
          data: anyNamed('data'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          onSendProgress: anyNamed('onSendProgress'),
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => response);
        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {
            'custom-name': 'custom-value',
          },
          httpClient: httpClient,
        );
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([AuthenticationStatus.authenticated]),
        );
        final actual = await fresh.onResponse(response);
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(httpClient.request('/mock/path', options: request)).called(1);
        verify(tokenStorage.write(token)).called(1);
      });

      test(
          'invokes wipes tokenStorage and sets authenticationStatus '
          'to unauthenticated when RevokeTokenException is thrown.', () async {
        var refreshCallCount = 0;
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        when(tokenStorage.delete()).thenAnswer((_) async => null);
        final response = MockResponse();
        when(response.statusCode).thenReturn(401);
        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            throw RevokeTokenException();
          },
          tokenHeader: (token) {
            return {};
          },
        );
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.authenticated,
          ]),
        );
        final actual = await fresh.onResponse(response);
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.unauthenticated,
          ]),
        );
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(tokenStorage.delete()).called(1);
      });

      test('returns null when token exists and response is null', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([
            AuthenticationStatus.authenticated,
          ]),
        );
        final actual = await fresh.onResponse(null);
        expect(actual, null);
      });
    });

    group('onError', () {
      test('returns error when token is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final error = MockDioError();
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onError(error);
        expect(actual, error);
      });

      test('returns error when shouldRefresh (default) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final error = MockDioError();
        final response = MockResponse();
        when(response.statusCode).thenReturn(200);
        when(error.response).thenReturn(response);
        final fresh = Fresh.oAuth2Token(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onError(error);
        expect(actual, error);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final request = MockRequestOptions();
        when(request.path).thenReturn('/mock/path');
        when(request.headers).thenReturn({});
        final error = MockDioError();
        final response = MockResponse();
        when(response.statusCode).thenReturn(401);
        when(error.response).thenReturn(response);
        when(response.request).thenReturn(request);
        final httpClient = MockHttpClient();
        when(httpClient.request(
          any,
          cancelToken: anyNamed('cancelToken'),
          data: anyNamed('data'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
          onSendProgress: anyNamed('onSendProgress'),
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => response);
        final fresh = Fresh<MockToken>(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return token;
          },
          tokenHeader: (_) => {
            'custom-name': 'custom-value',
          },
          httpClient: httpClient,
        );
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder([AuthenticationStatus.authenticated]),
        );
        final actual = await fresh.onError(error);
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(httpClient.request('/mock/path', options: request)).called(1);
        verify(tokenStorage.write(token)).called(1);
      });
    });
  });

  group('OoAuth2Token', () {
    test('throws AssertionError when accessToken is null', () {
      expect(
        () => OAuth2Token(accessToken: null),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
