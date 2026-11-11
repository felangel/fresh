import 'dart:async';

import 'package:fresh_http/fresh_http.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('token session', () {
    const tokenA = OAuth2Token(accessToken: 'a');
    const expiredA = OAuth2Token(accessToken: 'a.expired');
    const refreshedA = OAuth2Token(accessToken: 'a.refreshed');
    const tokenB = OAuth2Token(accessToken: 'b');
    final url = Uri.parse('http://example.com');

    late List<String?> sent;
    late List<Completer<int>> responses;
    late Completer<OAuth2Token> refresh;
    late int refreshCount;
    late Fresh<OAuth2Token> fresh;

    setUp(() {
      sent = [];
      responses = [];
      refresh = Completer<OAuth2Token>();
      refreshCount = 0;
      fresh = Fresh.oAuth2(
        tokenStorage: InMemoryTokenStorage<OAuth2Token>(),
        refreshToken: (_, __) {
          refreshCount++;
          return refresh.future;
        },
        shouldRefreshBeforeRequest: (_, token) => token == expiredA,
        httpClient: _PendingClient((request) {
          sent.add(request.headers['authorization']);
          responses.add(Completer<int>());
          return responses.last.future;
        }),
      );
    });

    final throwsReplaced = throwsA(
      isA<http.ClientException>().having(
        (e) => e.message,
        'message',
        'The token was replaced while the request was in flight.',
      ),
    );

    test('sends a request started just before the token is cleared', () async {
      await fresh.setToken(tokenA);

      final response = fresh.get(url);
      unawaited(fresh.clearToken());
      await pumpEventQueue();
      responses.single.complete(200);

      expect((await response).statusCode, 200);
      expect(sent, ['bearer a']);
    });

    test('does not refresh before a request once the token is replaced',
        () async {
      await fresh.setToken(expiredA);

      final response = fresh.get(url);
      unawaited(fresh.setToken(tokenB));

      await expectLater(response, throwsReplaced);
      expect(refreshCount, 0);
      expect(sent, isEmpty);
    });

    test('does not send a request whose refresh outlived its session',
        () async {
      await fresh.setToken(expiredA);

      final response = fresh.get(url);
      await pumpEventQueue();
      await fresh.clearToken();
      refresh.complete(refreshedA);

      await expectLater(response, throwsReplaced);
      expect(sent, isEmpty);
      expect(await fresh.token, isNull);
    });

    test('does not refresh after a 401 once the token is replaced', () async {
      await fresh.setToken(tokenA);

      final response = fresh.get(url);
      await pumpEventQueue();
      await fresh.setToken(tokenB);
      responses.single.complete(401);

      await expectLater(response, throwsReplaced);
      expect(refreshCount, 0);
      expect(sent, ['bearer a']);
    });

    test('does not retry with a token set during the refresh', () async {
      await fresh.setToken(tokenA);

      final response = fresh.get(url);
      await pumpEventQueue();
      responses.single.complete(401);
      await pumpEventQueue();
      await fresh.setToken(tokenB);
      refresh.complete(refreshedA);

      await expectLater(response, throwsReplaced);
      expect(sent, ['bearer a']);
      expect(await fresh.token, tokenB);
    });

    test('retries with the refreshed token within the same session', () async {
      await fresh.setToken(tokenA);

      final response = fresh.get(url);
      await pumpEventQueue();
      responses.single.complete(401);
      refresh.complete(refreshedA);
      await pumpEventQueue();
      responses.last.complete(200);

      expect((await response).statusCode, 200);
      expect(sent, ['bearer a', 'bearer a.refreshed']);
    });
  });
}

class _PendingClient extends http.BaseClient {
  _PendingClient(this._handler);

  final Future<int> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      const Stream.empty(),
      await _handler(request),
      request: request,
    );
  }
}
