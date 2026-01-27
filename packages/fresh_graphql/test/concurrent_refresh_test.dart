// ignore_for_file: must_be_immutable

import 'dart:async';

import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRequest extends Mock implements Request {
  MockRequest({this.context = const Context()});

  final Map<String, String> headers = {};

  @override
  final Context context;

  @override
  Request updateContextEntry<T extends ContextEntry>(
    ContextUpdater<T?> update,
  ) {
    final entry = update(context.entry<T>());
    if (entry is HttpLinkHeaders) {
      headers.addAll(entry.headers);
    }
    if (entry == null) return this;
    return MockRequest(context: context.withEntry(entry));
  }
}

class MockResponse extends Mock implements Response {
  MockResponse({this.errors, this.data});

  @override
  final List<GraphQLError>? errors;

  @override
  final Map<String, dynamic>? data;
}

void main() {
  group('Concurrent Refresh', () {
    test(
      'refreshToken is called exactly once when 3 parallel operations '
      'all trigger refresh',
      () async {
        var refreshCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>();

        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          shouldRefresh: (response) =>
              response.errors?.any(
                (e) => e.message.contains('UNAUTHENTICATED'),
              ) ??
              false,
        );

        await freshLink.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        var forwardCallCount = 0;

        // Mock forward link that returns auth error first,
        // success after refresh
        Stream<Response> mockForward(Request request) async* {
          forwardCallCount++;
          final authHeader = request.context
              .entry<HttpLinkHeaders>()
              ?.headers['authorization'];

          if (authHeader == 'bearer new.token.jwt') {
            yield MockResponse(data: {'result': 'success'});
          } else {
            yield MockResponse(
              errors: [const GraphQLError(message: 'UNAUTHENTICATED')],
            );
          }
        }

        // Launch 3 parallel operations
        final request1 = MockRequest();
        final request2 = MockRequest();
        final request3 = MockRequest();

        final stream1 = freshLink.request(request1, mockForward);
        final stream2 = freshLink.request(request2, mockForward);
        final stream3 = freshLink.request(request3, mockForward);

        // Start listening to all streams
        final future1 = stream1.toList();
        final future2 = stream2.toList();
        final future3 = stream3.toList();

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Complete the refresh with a new token
        refreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final results = await Future.wait([future1, future2, future3]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Streams hung'),
        );

        // All 3 operations should complete
        expect(results.length, equals(3));

        // Each stream should have yielded responses
        for (final result in results) {
          expect(result, isNotEmpty);
        }

        // refreshToken must be called exactly once
        expect(refreshCallCount, equals(1));

        // We expect:
        // - 3 initial calls that return UNAUTHENTICATED
        // - 3 retry calls after refresh
        expect(forwardCallCount, equals(6));
      },
    );

    test(
      'operations arriving while refresh is in-flight await the same refresh',
      () async {
        var refreshCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>();

        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          shouldRefresh: (response) =>
              response.errors?.any(
                (e) => e.message.contains('UNAUTHENTICATED'),
              ) ??
              false,
        );

        await freshLink.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        Stream<Response> mockForward(Request request) async* {
          final authHeader = request.context
              .entry<HttpLinkHeaders>()
              ?.headers['authorization'];

          if (authHeader == 'bearer new.token.jwt') {
            yield MockResponse(data: {'result': 'success'});
          } else {
            yield MockResponse(
              errors: [const GraphQLError(message: 'UNAUTHENTICATED')],
            );
          }
        }

        // Start first operation - it will trigger refresh
        final request1 = MockRequest();
        final future1 = freshLink.request(request1, mockForward).toList();

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(refreshCallCount, equals(1));

        // Start second operation while refresh is in-flight
        final request2 = MockRequest();
        final future2 = freshLink.request(request2, mockForward).toList();

        // Wait a bit
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Start third operation while refresh is still in-flight
        final request3 = MockRequest();
        final future3 = freshLink.request(request3, mockForward).toList();

        // Complete the refresh
        refreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final results = await Future.wait([future1, future2, future3]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Streams hung'),
        );

        // All operations should complete
        expect(results.length, equals(3));

        // refreshToken must still be called exactly once
        expect(refreshCallCount, equals(1));
      },
    );

    test(
      'RevokeTokenException: refresh called once, token revoked once, '
      'all operations complete without hanging',
      () async {
        var refreshCallCount = 0;
        var revokeCallCount = 0;
        final refreshCompleter = Completer<OAuth2Token>();
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>()
          ..onDelete = () => revokeCallCount++;

        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return refreshCompleter.future;
          },
          shouldRefresh: (response) =>
              response.errors?.any(
                (e) => e.message.contains('UNAUTHENTICATED'),
              ) ??
              false,
        );

        await freshLink.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        Stream<Response> mockForward(Request request) async* {
          yield MockResponse(
            errors: [const GraphQLError(message: 'UNAUTHENTICATED')],
          );
        }

        // Launch 3 parallel operations
        final request1 = MockRequest();
        final request2 = MockRequest();
        final request3 = MockRequest();

        final future1 = freshLink.request(request1, mockForward).toList();
        final future2 = freshLink.request(request2, mockForward).toList();
        final future3 = freshLink.request(request3, mockForward).toList();

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Complete refresh with RevokeTokenException
        refreshCompleter.completeError(RevokeTokenException());

        // All operations should complete (not hang)
        final results = await Future.wait([future1, future2, future3]).timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Streams hung after RevokeTokenException'),
        );

        // All operations should complete
        expect(results.length, equals(3));

        // refreshToken must be called exactly once
        expect(refreshCallCount, equals(1));

        // token should be revoked exactly once
        expect(revokeCallCount, equals(1));
      },
    );

    test(
      'refresh throws other exception: state resets, no hang',
      () async {
        var refreshCallCount = 0;
        final firstRefreshCompleter = Completer<OAuth2Token>();
        final secondRefreshCompleter = Completer<OAuth2Token>();
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>();

        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            if (refreshCallCount == 1) {
              return firstRefreshCompleter.future;
            }
            return secondRefreshCompleter.future;
          },
          shouldRefresh: (response) =>
              response.errors?.any(
                (e) => e.message.contains('UNAUTHENTICATED'),
              ) ??
              false,
        );

        await freshLink.setToken(
          const OAuth2Token(
            accessToken: 'expired.token.jwt',
            refreshToken: 'refreshToken',
          ),
        );

        Stream<Response> mockForward(Request request) async* {
          final authHeader = request.context
              .entry<HttpLinkHeaders>()
              ?.headers['authorization'];

          if (authHeader == 'bearer new.token.jwt') {
            yield MockResponse(data: {'result': 'success'});
          } else {
            yield MockResponse(
              errors: [const GraphQLError(message: 'UNAUTHENTICATED')],
            );
          }
        }

        // First operation triggers refresh that will fail
        final request1 = MockRequest();
        final future1 = freshLink.request(request1, mockForward).toList();

        // Wait for refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Complete refresh with generic exception
        firstRefreshCompleter.completeError(Exception('Network error'));

        // First operation should complete (returning original error response)
        final result1 = await future1.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Stream hung'),
        );
        expect(result1, isNotEmpty);
        expect(result1.first.errors, isNotNull);

        // State should be reset - second operation should trigger new refresh
        final request2 = MockRequest();
        final future2 = freshLink.request(request2, mockForward).toList();

        // Wait for second refresh to be triggered
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(refreshCallCount, equals(2));

        // Complete second refresh successfully
        secondRefreshCompleter.complete(
          const OAuth2Token(
            accessToken: 'new.token.jwt',
            refreshToken: 'newRefreshToken',
          ),
        );

        final result2 = await future2;
        expect(result2, isNotEmpty);
        expect(result2.last.data, isNotNull);
      },
    );

    test(
      'after successful refresh, a later auth error triggers a new refresh',
      () async {
        var refreshCallCount = 0;
        var requestCount = 0;
        final tokenStorage = _TrackingTokenStorage<OAuth2Token>();

        var currentToken = const OAuth2Token(
          accessToken: 'initial.token.jwt',
          refreshToken: 'refreshToken',
        );

        final freshLink = FreshLink.oAuth2(
          tokenStorage: tokenStorage,
          refreshToken: (_, __) async {
            refreshCallCount++;
            return currentToken = OAuth2Token(
              accessToken: 'token-$refreshCallCount.jwt',
              refreshToken: 'refreshToken',
            );
          },
          shouldRefresh: (response) =>
              response.errors?.any(
                (e) => e.message.contains('UNAUTHENTICATED'),
              ) ??
              false,
        );

        await freshLink.setToken(currentToken);

        Stream<Response> mockForward(Request request) async* {
          requestCount++;
          final authHeader = request.context
              .entry<HttpLinkHeaders>()
              ?.headers['authorization'];

          // First 2 requests (initial + retry after first refresh) succeed
          // Third request (with token-1) fails to simulate expiry
          // Fourth request (retry with token-2) succeeds
          if (authHeader == 'bearer token-1.jwt' && requestCount == 2) {
            yield MockResponse(data: {'result': 'success'});
          } else if (authHeader == 'bearer token-2.jwt') {
            yield MockResponse(data: {'result': 'success'});
          } else {
            yield MockResponse(
              errors: [const GraphQLError(message: 'UNAUTHENTICATED')],
            );
          }
        }

        // First operation - gets auth error, triggers first refresh,
        // retry succeeds
        final request1 = MockRequest();
        final result1 = await freshLink.request(request1, mockForward).toList();
        expect(result1.last.data, isNotNull);
        expect(refreshCallCount, equals(1));

        // Wait a bit between operations
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Second operation - gets auth error, triggers second refresh
        final request2 = MockRequest();
        final result2 = await freshLink.request(request2, mockForward).toList();
        expect(result2.last.data, isNotNull);
        expect(refreshCallCount, equals(2));
      },
    );
  });
}

class _TrackingTokenStorage<T> implements TokenStorage<T> {
  T? _token;
  void Function()? onDelete;

  @override
  Future<void> delete() async {
    _token = null;
    onDelete?.call();
  }

  @override
  Future<T?> read() async {
    return _token;
  }

  @override
  Future<void> write(T token) async {
    _token = token;
  }
}
