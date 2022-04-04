import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';

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

    on<AuthenticationStatusChanged>(_onAuthenticationStatusChanged);
    on<LoggedOut>(_onLoggedOut);
  }

  late StreamSubscription<UserAuthenticationStatus> _subscription;
  final UserRepository _userRepository;

  void _onAuthenticationStatusChanged(
    AuthenticationStatusChanged event,
    Emitter<AuthenticationState> emit,
  ) {
    switch (event.authenticationStatus) {
      case UserAuthenticationStatus.signedIn:
        return emit(AuthenticationAuthenticated());
      case UserAuthenticationStatus.signedOut:
        return emit(AuthenticationUnauthenticated());
      case UserAuthenticationStatus.unknown:
        return emit(AuthenticationUnknown());
    }
  }

  void _onLoggedOut(
    LoggedOut event,
    Emitter<AuthenticationState> emit,
  ) {
    _userRepository.signOut().ignore();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
