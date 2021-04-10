import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';
import 'package:very_good_analysis/very_good_analysis.dart';

part 'authentication_event.dart';
part 'authentication_state.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  AuthenticationBloc(UserRepository userRepository)
      : _userRepository = userRepository,
        super(AuthenticationUnknown()) {
    _subscription = _userRepository.authenticationStatus.listen((status) {
      add(AuthenticationStatusChanged(status));
    });
  }

  late StreamSubscription<UserAuthenticationStatus> _subscription;
  final UserRepository _userRepository;

  @override
  Stream<AuthenticationState> mapEventToState(
    AuthenticationEvent event,
  ) async* {
    if (event is AuthenticationStatusChanged) {
      yield _mapAuthenticationStatusChangedToState(event);
    } else if (event is LoggedOut) {
      unawaited(_userRepository.signOut());
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

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
