import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';

part 'authentication_event.dart';
part 'authentication_state.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  AuthenticationBloc(UserRepository userRepository)
      : assert(userRepository != null),
        _userRepository = userRepository {
    _subscription = _userRepository.authenticationStatus.listen((status) {
      add(AuthenticationStatusChanged(status));
    });
  }

  StreamSubscription<UserAuthenticationStatus> _subscription;
  final UserRepository _userRepository;

  @override
  AuthenticationState get initialState => AuthenticationUnknown();

  @override
  Stream<AuthenticationState> mapEventToState(
    AuthenticationEvent event,
  ) async* {
    if (event is AuthenticationStatusChanged) {
      yield _mapAuthenticationStatusChangedToState(event);
    } else if (event is LoggedOut) {
      yield _mapLoggedOutToState();
    }
  }

  AuthenticationState _mapAuthenticationStatusChangedToState(
    AuthenticationStatusChanged event,
  ) {
    switch (event.authenticationStatus) {
      case UserAuthenticationStatus.signedIn:
        return AuthenticationAuthenticated();
      case UserAuthenticationStatus.signedOut:
        return AuthenticationUnauthenticated();
      case UserAuthenticationStatus.unknown:
      default:
        return AuthenticationUnknown();
    }
  }

  AuthenticationState _mapLoggedOutToState() {
    _userRepository.signOut();
    return AuthenticationUnauthenticated();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
