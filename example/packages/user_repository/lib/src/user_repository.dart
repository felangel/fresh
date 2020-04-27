import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';
import 'package:meta/meta.dart';

enum UserAuthenticationStatus {
  unknown,
  signedIn,
  signedOut,
}

class UserRepository {
  UserRepository(JsonplaceholderClient jsonPlaceholderClient)
      : _jsonplaceholderClient = jsonPlaceholderClient;

  final JsonplaceholderClient _jsonplaceholderClient;

  Stream<UserAuthenticationStatus> get authenticationStatus {
    return _jsonplaceholderClient.authenticationStatus.map((status) {
      switch (status) {
        case AuthenticationStatus.authenticated:
          return UserAuthenticationStatus.signedIn;
        case AuthenticationStatus.unauthenticated:
          return UserAuthenticationStatus.signedOut;
        case AuthenticationStatus.initial:
        default:
          return UserAuthenticationStatus.unknown;
      }
    });
  }

  Future<void> signIn({
    @required String username,
    @required String password,
  }) async {
    await _jsonplaceholderClient.authenticate(
      username: username,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _jsonplaceholderClient.unauthenticate();
  }
}
