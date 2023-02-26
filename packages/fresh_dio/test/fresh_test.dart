import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTokenStorage<T> extends Mock implements TokenStorage<T> {}

class MockToken extends Mock implements OAuth2Token {}

class MockRequestOptions extends Mock implements RequestOptions {}

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

class MockOptions extends Mock implements BaseOptions {}

class MockResponse<T> extends Mock implements Response<T> {}

class MockResponseInterceptorHandler extends Mock
    implements ResponseInterceptorHandler {}

class MockDioError extends Mock implements DioError {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

class MockHttpClient extends Mock implements Dio {}

class FakeRequestOptions extends Fake implements RequestOptions {}

class FakeResponse<T> extends Fake implements Response<T> {}

class FakeDioError extends Fake implements DioError {}

Future<OAuth2Token> emptyRefreshToken(OAuth2Token? _, Dio __) async {
  return MockToken();
}

void main() {
  group('Fresh', () {
    late TokenStorage<OAuth2Token> tokenStorage;
    late RequestInterceptorHandler requestHandler;
    late ResponseInterceptorHandler responseHandler;
    late ErrorInterceptorHandler errorHandler;

    setUpAll(() {
      registerFallbackValue(MockToken());
      registerFallbackValue(MockToken());
      registerFallbackValue(FakeRequestOptions());
      registerFallbackValue(FakeResponse<dynamic>());
      registerFallbackValue(FakeDioError());
    });

    setUp(() {
      tokenStorage = MockTokenStorage<OAuth2Token>();
      requestHandler = MockRequestInterceptorHandler();
      responseHandler = MockResponseInterceptorHandler();
      errorHandler = MockErrorInterceptorHandler();
    });

    group('configure token', () {
      group('setToken', () {
        test('invokes tokenStorage.write', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          final token = MockToken();
          final fresh = Fresh.oAuth2(
            tokenStorage: tokenStorage,
            refreshToken: emptyRefreshToken,
          );
          await fresh.setToken(token);
          verify(() => tokenStorage.write(token)).called(1);
        });

        test('adds unauthenticated status when call setToken(null)', () async {
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});
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
          when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
          when(() => tokenStorage.write(any())).thenAnswer((_) async {});
          when(() => tokenStorage.delete()).thenAnswer((_) async {});
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
        final options = RequestOptions(path: '');
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.onRequest(options, requestHandler);
        final result = verify(() => requestHandler.next(captureAny()))
          ..called(1);

        expect(
          (result.captured.first as RequestOptions).headers,
          {
            'content-type': 'application/json; charset=utf-8',
            'authorization': 'bearer accessToken',
          },
        );
      });

      test(
          'appends token header when token is OAuth2Token '
          'and tokenHeader is provided', () async {
        final options = RequestOptions(path: '');
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          tokenHeader: (_) => {'custom-header': 'custom-token'},
        );

        await fresh.onRequest(options, requestHandler);
        final result = verify(() => requestHandler.next(captureAny()))
          ..called(1);

        expect(
          (result.captured.first as RequestOptions).headers,
          {
            'content-type': 'application/json; charset=utf-8',
            'custom-header': 'custom-token',
          },
        );
      });

      test(
          'appends the standart header when token use OAuth2Token constructor '
          'but tokenHeader is not provided', () async {
        final options = RequestOptions(path: '');
        when(() => tokenStorage.read()).thenAnswer((_) async => oAuth2Token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.onRequest(options, requestHandler);
        final result = verify(() => requestHandler.next(captureAny()))
          ..called(1);

        expect(
          (result.captured.first as RequestOptions).headers,
          {
            'content-type': 'application/json; charset=utf-8',
            'authorization':
                '${oAuth2Token.tokenType} ${oAuth2Token.accessToken}',
          },
        );
      });
    });

    group('onResponse', () {
      test('returns untouched response when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final response = MockResponse<dynamic>();
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.next(captureAny()))
          ..called(1);

        expect(result.captured.first, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (default) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final response = MockResponse<dynamic>();
        when(() => response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.next(captureAny()))
          ..called(1);

        expect(result.captured.first, response);
      });

      test(
          'returns untouched response when '
          'shouldRefresh (custom) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final response = MockResponse<dynamic>();
        when(() => response.statusCode).thenReturn(200);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
          shouldRefresh: (_) => false,
        );

        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.next(captureAny()))
          ..called(1);

        expect(result.captured.first, response);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final request = MockRequestOptions();
        when(() => request.path).thenReturn('/mock/path');
        when(() => request.baseUrl).thenReturn('https://test.com');
        when(() => request.headers).thenReturn(<String, String>{});
        when(() => request.queryParameters).thenReturn(<String, String>{});
        when(() => request.method).thenReturn('GET');
        when(() => request.sendTimeout).thenReturn(Duration.zero);
        when(() => request.receiveTimeout).thenReturn(Duration.zero);
        when(() => request.extra).thenReturn(<String, String>{});
        when(() => request.responseType).thenReturn(ResponseType.json);
        when(() => request.validateStatus).thenReturn((_) => false);
        when(() => request.receiveDataWhenStatusError).thenReturn(false);
        when(() => request.followRedirects).thenReturn(false);
        when(() => request.maxRedirects).thenReturn(0);
        when(() => request.listFormat).thenReturn(ListFormat.csv);
        final response = MockResponse<dynamic>();
        when(() => response.statusCode).thenReturn(401);
        when(() => response.requestOptions).thenReturn(request);
        when(() => response.requestOptions).thenReturn(request);
        final options = MockOptions();
        final httpClient = MockHttpClient();
        when(() => httpClient.options).thenReturn(options);
        when(
          () => httpClient.request<dynamic>(
            any(),
            cancelToken: any(named: 'cancelToken'),
            data: any<dynamic>(named: 'data'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
            onSendProgress: any(named: 'onSendProgress'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => response);
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
        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.resolve(captureAny()))
          ..called(1);

        expect(refreshCallCount, 1);
        expect(result.captured.first, response);
        verify(() => options.baseUrl = 'https://test.com').called(1);
        verify(
          () => httpClient.request<dynamic>(
            '/mock/path',
            data: null,
            queryParameters: <String, String>{},
            cancelToken: null,
            onSendProgress: null,
            onReceiveProgress: null,
            options: any(named: 'options'),
          ),
        ).called(1);
        verify(() => tokenStorage.write(token)).called(1);
      });

      test(
          'invokes wipes tokenStorage and sets authenticationStatus '
          'to unauthenticated when RevokeTokenException is thrown.', () async {
        var refreshCallCount = 0;
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        when(tokenStorage.delete).thenAnswer((_) async {});
        final response = MockResponse<dynamic>();
        final request = MockRequestOptions();
        when(() => response.requestOptions).thenReturn(request);
        when(() => response.statusCode).thenReturn(401);
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

        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.reject(captureAny()))
          ..called(1);
        final actual = result.captured.first as DioError;
        await expectLater(
          fresh.authenticationStatus,
          emitsInOrder(const <AuthenticationStatus>[
            AuthenticationStatus.unauthenticated,
          ]),
        );
        expect(refreshCallCount, 1);
        expect(actual.requestOptions, request);
        expect(actual.response, response);
        expect(actual.error, isA<RevokeTokenException>());
        verify(tokenStorage.delete).called(1);
      });

      test('returns same response when token exists', () async {
        tokenStorage = MockTokenStorage<MockToken>();
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
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
        final response = MockResponse<dynamic>();
        await fresh.onResponse(response, responseHandler);
        final result = verify(() => responseHandler.next(captureAny()))
          ..called(1);
        expect(result.captured.first, response);
      });
    });

    group('onError', () {
      test('returns error when token is null', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final error = MockDioError();
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );

        await fresh.onError(error, errorHandler);
        final result = verify(() => errorHandler.next(captureAny()))..called(1);
        expect(result.captured.first, error);
      });

      test('returns error tryRefresh throws DioError', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        when(() => tokenStorage.delete()).thenAnswer((_) async {});
        final error = MockDioError();
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          shouldRefresh: (_) => true,
          refreshToken: (_, __) => throw RevokeTokenException(),
        );
        final request = MockRequestOptions();
        when(() => request.path).thenReturn('/mock/path');
        when(() => request.baseUrl).thenReturn('https://test.com');
        when(() => request.headers).thenReturn(<String, String>{});
        when(() => request.queryParameters).thenReturn(<String, String>{});
        when(() => request.method).thenReturn('GET');
        when(() => request.sendTimeout).thenReturn(Duration.zero);
        when(() => request.receiveTimeout).thenReturn(Duration.zero);
        when(() => request.extra).thenReturn(<String, String>{});
        when(() => request.responseType).thenReturn(ResponseType.json);
        when(() => request.validateStatus).thenReturn((_) => false);
        when(() => request.receiveDataWhenStatusError).thenReturn(false);
        when(() => request.followRedirects).thenReturn(false);
        when(() => request.maxRedirects).thenReturn(0);
        when(() => request.listFormat).thenReturn(ListFormat.csv);
        final response = MockResponse<dynamic>();
        when(() => response.requestOptions).thenReturn(request);
        when(() => error.response).thenReturn(response);
        await fresh.onError(error, errorHandler);
        final result = verify(() => errorHandler.next(captureAny()))..called(1);
        expect(result.captured.first, isA<DioError>());
      });

      test('returns error when error is RevokeTokenException', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final revokeTokenException = RevokeTokenException();
        final error = MockDioError();
        when<dynamic>(() => error.error).thenReturn(revokeTokenException);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await fresh.onError(error, errorHandler);
        final result = verify(() => errorHandler.next(captureAny()))..called(1);
        expect(result.captured.first, error);
      });

      test('returns error when shouldRefresh (default) is false', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => MockToken());
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final error = MockDioError();
        final response = MockResponse<dynamic>();
        when(() => response.statusCode).thenReturn(200);
        when(() => error.response).thenReturn(response);
        final fresh = Fresh.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: emptyRefreshToken,
        );
        await fresh.onError(error, errorHandler);
        final result = verify(() => errorHandler.next(captureAny()))..called(1);
        expect(result.captured.first, error);
      });

      test(
          'invokes refreshToken when token is not null '
          'and shouldRefresh (default) is true', () async {
        var refreshCallCount = 0;
        final token = MockToken();
        final tokenStorage = MockTokenStorage<MockToken>();
        when(tokenStorage.read).thenAnswer((_) async => token);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
        final request = MockRequestOptions();
        when(() => request.path).thenReturn('/mock/path');
        when(() => request.baseUrl).thenReturn('https://test.com');
        when(() => request.headers).thenReturn(<String, String>{});
        when(() => request.queryParameters).thenReturn(<String, String>{});
        when(() => request.method).thenReturn('GET');
        when(() => request.sendTimeout).thenReturn(Duration.zero);
        when(() => request.receiveTimeout).thenReturn(Duration.zero);
        when(() => request.extra).thenReturn(<String, String>{});
        when(() => request.responseType).thenReturn(ResponseType.json);
        when(() => request.validateStatus).thenReturn((_) => false);
        when(() => request.receiveDataWhenStatusError).thenReturn(false);
        when(() => request.followRedirects).thenReturn(false);
        when(() => request.maxRedirects).thenReturn(0);
        when(() => request.listFormat).thenReturn(ListFormat.csv);
        final error = MockDioError();
        final response = MockResponse<dynamic>();
        when(() => response.statusCode).thenReturn(401);
        when(() => error.response).thenReturn(response);
        when(() => response.requestOptions).thenReturn(request);
        final options = MockOptions();
        final httpClient = MockHttpClient();
        when(() => httpClient.options).thenReturn(options);
        when(
          () => httpClient.request<dynamic>(
            any(),
            cancelToken: any(named: 'cancelToken'),
            data: any<dynamic>(named: 'data'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
            onSendProgress: any(named: 'onSendProgress'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => response);
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
        await fresh.onError(error, errorHandler);
        final result = verify(() => errorHandler.resolve(captureAny()))
          ..called(1);
        final actual = result.captured.first as MockResponse;
        expect(refreshCallCount, 1);
        expect(actual, response);
        verify(() => options.baseUrl = 'https://test.com').called(1);
        verify(
          () => httpClient.request<dynamic>(
            '/mock/path',
            data: null,
            queryParameters: <String, String>{},
            cancelToken: null,
            onSendProgress: null,
            onReceiveProgress: null,
            options: any(named: 'options'),
          ),
        ).called(1);
        verify(() => tokenStorage.write(token)).called(1);
      });
    });

    group('close', () {
      test('shoud close streams', () async {
        when(() => tokenStorage.read()).thenAnswer((_) async => null);
        when(() => tokenStorage.write(any())).thenAnswer((_) async {});
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
}
