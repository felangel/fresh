part of 'authentication_bloc.dart';

abstract class AuthenticationEvent extends Equatable {
  @override
  List<Object> get props => [];

  @override
  bool get stringify => true;
}

class AuthenticationStatusChanged extends AuthenticationEvent {
  AuthenticationStatusChanged(this.authenticationStatus);

  final UserAuthenticationStatus authenticationStatus;

  @override
  List<Object> get props => [authenticationStatus];
}

class LoggedOut extends AuthenticationEvent {}
