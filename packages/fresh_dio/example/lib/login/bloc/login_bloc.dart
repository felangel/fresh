import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc(UserRepository userRepository)
      : _userRepository = userRepository,
        super(LoginState());

  final UserRepository _userRepository;

  @override
  Stream<LoginState> mapEventToState(
    LoginEvent event,
  ) async* {
    if (event is LoginUsernameChanged) {
      yield state.copyWith(username: event.username);
    } else if (event is LoginPasswordChanged) {
      yield state.copyWith(password: event.password);
    } else if (event is LoginSubmitted) {
      yield state.copyWith(status: LoginStatus.submissionInProgress);
      try {
        await _userRepository.signIn(
          username: state.username,
          password: state.password,
        );
        yield state.copyWith(status: LoginStatus.submissionSuccess);
      } on Exception catch (_) {
        yield state.copyWith(status: LoginStatus.submissionFailure);
      }
    }
  }
}
