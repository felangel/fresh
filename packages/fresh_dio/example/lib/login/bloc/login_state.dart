part of 'login_bloc.dart';

enum LoginStatus {
  initial,
  submissionInProgress,
  submissionSuccess,
  submissionFailure
}

class LoginState extends Equatable {
  const LoginState({
    this.username = '',
    this.password = '',
    this.status = LoginStatus.initial,
  });

  final LoginStatus status;
  final String username;
  final String password;

  bool get submissionEnabled =>
      status != LoginStatus.submissionInProgress &&
      username.isNotEmpty &&
      password.isNotEmpty;

  LoginState copyWith({
    LoginStatus? status,
    String? username,
    String? password,
  }) {
    return LoginState(
      status: status ?? this.status,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  @override
  List<Object> get props => [status, username, password];

  @override
  bool get stringify => true;
}
