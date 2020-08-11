import 'package:dio/dio.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockToken extends Mock implements OAuth2Token {}

class MockRequestOptions extends Mock implements RequestOptions {}

class MockResponse<T> extends Mock implements Response<T> {}

class MockDioError extends Mock implements DioError {}

class MockHttpClient extends Mock implements Dio {}

Future<T> emptyRefreshToken<T>(dynamic _, dynamic __) async => null;

void main() {
  group('Fresh', () {
    TokenStorage<OAuth2Token> tokenStorage;

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
    });

    test('throws AssertionError when tokenStorage is null', () {
      expect(
        () => Fresh.oAuth2(tokenStorage: null, refreshToken: emptyRefreshToken),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when refreshToken is null', () {
      expect(
        () => Fresh.oAuth2(tokenStorage: tokenStorage, refreshToken: null),
        throwsA(isA<AssertionError>()),
      );
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final token = MockToken();
          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await fresh.setToken(token);
          verify(tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await fresh.setToken(null);
          await expectLater(
            fresh.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });

      group('clearToken', () {
        test('adds unauthenticated status when call clearToken()', () async {
          when(tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(tokenStorage.write(any)).thenAnswer((_) async => null);
          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await fresh.clearToken();
          await expectLater(
            fresh.authenticationStatus,
            emitsInOrder(const <AuthenticationStatus>[
              AuthenticationStatus.unauthenticated,
            ]),
          );
        });
      });
    });

    group('onRequest', () {
      const oAuth2Token = OAuth2Token(accessToken: 'accessToken');
      test(
          'appends token header when token is OAuth2Token '
          'and tokenHeader is not provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2(
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
          'appends token header when token is OAuth2Token '
          'and tokenHeader is provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2(
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
          'appends the standart header when token use OAuth2Token constructor'
          'but tokenHeader is not provided', () async {
        final options = RequestOptions();
        when(tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onRequest(options) as RequestOptions;
        expect(
          actual.headers,
          {
            'content-type': null,
            'authorization':
                '${oAuth2Token.tokenType} ${oAuth2Token.accessToken}',
          },
        );
      });

      test('throws AssertionError when tokenHeader is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);

        expect(
          () {
            Fresh<OAuth2Token>(
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
        final response = MockResponse<dynamic>();
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onResponse(response) as MockResponse;
        expect(actual, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (default) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final response = MockResponse<dynamic>();
        when(response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onResponse(response) as MockResponse;
        expect(actual, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (custom) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final response = MockResponse<dynamic>();
        when(response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          shouldRefresh: (_) => false,
        );
        final actual = await fresh.onResponse(response) as MockResponse;
        expect(actual, response);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final request = MockRequestOptions();
        when(request.path).thenReturn('/mock/path');
        when(request.headers).thenReturn(<String, String>{});
        final response = MockResponse<dynamic>();
        when(response.statusCode).thenReturn(401);
        when(response.request).thenReturn(request);
        final httpClient = MockHttpClient();
        when(httpClient.request<dynamic>(
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
          emitsInOrder(
            const <AuthenticationStatus>[AuthenticationStatus.authenticated],
          ),
        );
        final actual = await fresh.onResponse(response) as MockResponse;
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(httpClient.request<dynamic>('/mock/path', options: request))
            .called(1);
        verify(tokenStorage.write(token)).called(1);
      });

      test(
          'invokes wipes tokenStorage and sets authenticationStatus '
          'to unauthenticated when RevokeTokenException is thrown.', () async {
        var refreshCallCount = 0;
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        when(tokenStorage.delete()).thenAnswer((_) async => null);
        final response = MockResponse<dynamic>();
        final request = MockRequestOptions();
        when(response.request).thenReturn(request);
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
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );
        final actual = await fresh.onResponse(response) as DioError;
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );
        expect(refreshCallCount, 1);
        expect(actual.request, request);
        expect(actual.response, response);
        expect(actual.error, isA<RevokeTokenException>());
        verify(tokenStorage.delete()).called(1);
      });

      test('returns null when token exists and response is null', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.authenticated,
          ]),
        );
        final actual = await fresh.onResponse(null) as MockResponse;
        expect(actual, null);
      });
    });

    group('onError', () {
      test('returns error when token is null', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final error = MockDioError();
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onError(error) as MockDioError;
        expect(actual, error);
      });

      test('returns error when error is RevokeTokenException', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final revokeTokenException = RevokeTokenException();
        final error = MockDioError();
        when<dynamic>(error.error).thenReturn(revokeTokenException);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onError(error) as MockDioError;
        expect(actual, error);
      });

      test('returns error when shouldRefresh (default) is false', () async {
        when(tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final error = MockDioError();
        final response = MockResponse<dynamic>();
        when(response.statusCode).thenReturn(200);
        when(error.response).thenReturn(response);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        final actual = await fresh.onError(error) as MockDioError;
        expect(actual, error);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read()).thenAnswer((_) async => token);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final request = MockRequestOptions();
        when(request.path).thenReturn('/mock/path');
        when(request.headers).thenReturn(<String, String>{});
        final error = MockDioError();
        final response = MockResponse<dynamic>();
        when(response.statusCode).thenReturn(401);
        when(error.response).thenReturn(response);
        when(response.request).thenReturn(request);
        final httpClient = MockHttpClient();
        when(httpClient.request<dynamic>(
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
          emitsInOrder(
            const <AuthenticationStatus>[
              AuthenticationStatus.authenticated,
            ],
          ),
        );
        final actual = await fresh.onError(error) as MockResponse;
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(httpClient.request<dynamic>('/mock/path', options: request))
            .called(1);
        verify(tokenStorage.write(token)).called(1);
      });
    });

    group('close', () {
      test('shoud close streams', () async {
        when(tokenStorage.read()).thenAnswer((_) async => null);
        when(tokenStorage.write(any)).thenAnswer((_) async => null);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        final mockToken = MockToken();
        await fresh.setToken(mockToken);
        await fresh.close();

        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(<Matcher>[
            equals(AuthenticationStatus.authenticated),
            emitsDone,
          ]),
        );
      });
    });
  });

  group('OAuth2Token', () {
    test('throws AssertionError when accessToken is null', () {
      expect(
        () => OAuth2Token(accessToken: null),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
