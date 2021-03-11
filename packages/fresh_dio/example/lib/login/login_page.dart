import 'package:flutter/material.dart';
import 'package:fresh_example/login/bloc/login_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:user_repository/user_repository.dart';

class LoginPage extends StatelessWidget {
  static Route route() {
    return MaterialPageRoute(builder: (_) => LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: BlocProvider(
        create: (context) => LoginBloc(context.read<UserRepository>()),
        child: Login(),
      ),
    );
  }
}

class Login extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state.status == LoginStatus.submissionFailure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: const Text('Login Failure')));
        }
      },
      child: Column(
        children: <Widget>[
          TextField(
            onChanged: (value) {
              context.read<LoginBloc>().add(LoginUsernameChanged(value));
            },
            decoration: InputDecoration(labelText: 'Username'),
          ),
          TextField(
            onChanged: (value) {
              context.read<LoginBloc>().add(LoginPasswordChanged(value));
            },
            decoration: InputDecoration(labelText: 'Password'),
          ),
          BlocBuilder<LoginBloc, LoginState>(
            builder: (context, state) {
              return ElevatedButton(
                child: state.status == LoginStatus.submissionInProgress
                    ? const CircularProgressIndicator()
                    : const Text('Login'),
                onPressed: state.submissionEnabled
                    ? () => context.read<LoginBloc>().add(LoginSubmitted())
                    : null,
              );
            },
          )
        ],
      ),
    );
  }
}
