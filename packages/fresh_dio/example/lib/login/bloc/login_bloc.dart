import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc(UserRepository userRepository)
      : _userRepository = userRepository,
        super(const LoginState()) {
    on<LoginUsernameChanged>(_onLoginUsernameChanged);
    on<LoginPasswordChanged>(_onLoginPasswordChanged);
    on<LoginSubmitted>(_onLoginSubmitted);
  }

  final UserRepository _userRepository;

  void _onLoginUsernameChanged(
    LoginUsernameChanged event,
    Emitter<LoginState> emit,
  ) {
    emit(state.copyWith(username: event.username));
  }

  void _onLoginPasswordChanged(
    LoginPasswordChanged event,
    Emitter<LoginState> emit,
  ) {
    emit(state.copyWith(password: event.password));
  }

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    emit(state.copyWith(status: LoginStatus.submissionInProgress));
    try {
      await _userRepository.signIn(
        username: state.username,
        password: state.password,
      );
      emit(state.copyWith(status: LoginStatus.submissionSuccess));
    } catch (_) {
      emit(state.copyWith(status: LoginStatus.submissionFailure));
    }
  }
}
