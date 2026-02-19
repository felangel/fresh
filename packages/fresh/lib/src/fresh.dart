import 'dart:async';

/// An Exception that should be thrown when overriding `refreshToken` if the
/// refresh fails and should result in a force-logout.
class RevokeTokenException implements Exception {}

/// Enum representing the current authentication status of the application.
enum AuthenticationStatus {
  /// The status before the true [AuthenticationStatus] has been determined.
  initial,

  /// The status when the application is not authenticated.
  unauthenticated,

  /// The status when the application is authenticated.
  authenticated
}

/// An interface which must be implemented to
/// read, write, and delete the `Token`.
abstract class TokenStorage<T> {
  /// Returns the stored token asynchronously.
  Future<T?> read();

  /// Saves the provided [token] asynchronously.
  Future<void> write(T token);

  /// Deletes the stored token asynchronously.
  Future<void> delete();
}

/// Function responsible for building the token header(s) give a [token].
typedef TokenHeaderBuilder<T> = Map<String, String> Function(
  T token,
);

/// A [TokenStorage] implementation that keeps the token in memory.
class InMemoryTokenStorage<T> implements TokenStorage<T> {
  T? _token;

  @override
  Future<void> delete() async {
    _token = null;
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

/// {@template fresh_mixin}
/// A mixin which handles core token refresh functionality.
/// {@endtemplate}
mixin FreshMixin<T> {
  AuthenticationStatus _authenticationStatus = AuthenticationStatus.initial;

  late TokenStorage<T> _tokenStorage;

  T? _token;

  /// In-flight refresh future for single-flight coordination.
  /// When a refresh is in progress, this holds the future that all
  /// concurrent refresh requests will await.
  Future<T>? _refreshFuture;

  final StreamController<AuthenticationStatus> _controller =
      StreamController<AuthenticationStatus>.broadcast()
        ..add(AuthenticationStatus.initial);

  /// Setter for the [TokenStorage] instance.
  set tokenStorage(TokenStorage<T> tokenStorage) {
    _tokenStorage = tokenStorage..read().then(_updateStatus);
  }

  /// Returns the current token.
  Future<T?> get token async {
    if (_authenticationStatus != AuthenticationStatus.initial) return _token;
    await authenticationStatus.firstWhere(
      (status) => status != AuthenticationStatus.initial,
    );
    return _token;
  }

  /// Returns a [Stream<AuthenticationStatus>] which can be used to get notified
  /// of changes to the authentication state based on the presence/absence of a token.
  Stream<AuthenticationStatus> get authenticationStatus async* {
    yield _authenticationStatus;
    yield* _controller.stream;
  }

  /// Sets the internal [token] to the provided [token]
  /// and updates the [AuthenticationStatus] accordingly.
  ///
  /// If the provided token is null, the [AuthenticationStatus] will be updated
  /// to `unauthenticated` and the token will be removed from storage, otherwise
  /// it will be updated to `authenticated`and save to storage.
  Future<void> setToken(T? token) async {
    if (token == null) return clearToken();
    await _tokenStorage.write(token);
    _updateStatus(token);
  }

  /// Delete the storaged [token]. and emit the
  /// `AuthenticationStatus.unauthenticated` if authenticationStatus
  /// not is `AuthenticationStatus.unauthenticated`
  /// This method should be called when the token is no longer valid.
  Future<void> revokeToken() async {
    await _tokenStorage.delete();
    if (_authenticationStatus != AuthenticationStatus.unauthenticated) {
      _authenticationStatus = AuthenticationStatus.unauthenticated;
      _controller.add(_authenticationStatus);
    }
  }

  /// Clears token storage and updates the [AuthenticationStatus]
  /// to [AuthenticationStatus.unauthenticated].
  Future<void> clearToken() async {
    await _tokenStorage.delete();
    _updateStatus(null);
  }

  /// Closes Fresh StreamController.
  ///
  /// [setToken] and [clearToken] must not be called after this method.
  ///
  /// Calling this method more than once is allowed, but does nothing.
  Future<void> close() => _controller.close();

  /// Performs a single-flight token refresh.
  ///
  /// If a refresh is already in progress, this will return the same future
  /// that the in-flight refresh will complete with. This ensures that
  /// concurrent refresh requests result in only one actual refresh operation.
  ///
  /// Additionally, if the token has already been refreshed by a previous
  /// request (detected by comparing with [tokenBeforeRefresh]), this will
  /// return the current token without triggering a new refresh.
  ///
  /// The [refreshAction] callback is invoked to perform the actual refresh.
  /// It receives the current token and should return the new token.
  ///
  /// The [tokenBeforeRefresh] parameter should be the token value that was
  /// used when the request that triggered this refresh was made. This allows
  /// detection of cases where another request has already refreshed the token.
  ///
  /// If the refresh succeeds, the new token is automatically saved via
  /// [setToken] and returned.
  ///
  /// If the refresh fails:
  /// - If a [RevokeTokenException] is thrown, [clearToken] is called
  ///   and the exception is rethrown.
  /// - For any other exception, the exception is rethrown without
  ///   clearing the token.
  ///
  /// In all cases (success or failure), the in-flight refresh state is
  /// cleared in a `finally` block, ensuring no deadlocks.
  Future<T> singleFlightRefresh(
    Future<T> Function(T? token) refreshAction, {
    T? tokenBeforeRefresh,
  }) async {
    // Check if we already have a different token than what was used for the
    // request. This means another request already refreshed the token.
    if (tokenBeforeRefresh != null && _token != tokenBeforeRefresh) {
      // Token has already been refreshed, return the current token
      if (_token != null) {
        return _token as T;
      }
    }

    // If a refresh is already in progress, await it
    final existingFuture = _refreshFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    // Start a new refresh - create and store the future immediately
    // before any await to prevent race conditions
    final future = _performRefresh(refreshAction);
    _refreshFuture = future;
    return future;
  }

  Future<T> _performRefresh(Future<T> Function(T? token) refreshAction) async {
    try {
      final refreshedToken = await refreshAction(_token);
      await setToken(refreshedToken);
      return refreshedToken;
    } on RevokeTokenException {
      await clearToken();
      rethrow;
    } finally {
      _refreshFuture = null;
    }
  }

  /// Update the internal [token] and updates the
  /// [AuthenticationStatus] accordingly.
  ///
  /// If the provided token is null, the [AuthenticationStatus] will
  /// be updated to `AuthenticationStatus.unauthenticated` otherwise it
  /// will be updated to `AuthenticationStatus.authenticated`.
  void _updateStatus(T? token) {
    _authenticationStatus = token != null
        ? AuthenticationStatus.authenticated
        : AuthenticationStatus.unauthenticated;
    _token = token;
    _controller.add(_authenticationStatus);
  }
}
