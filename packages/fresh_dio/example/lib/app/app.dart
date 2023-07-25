import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fresh_example/authentication/bloc/authentication_bloc.dart';
import 'package:fresh_example/login/login_page.dart';
import 'package:fresh_example/photos/photos_page.dart';
import 'package:fresh_example/splash/splash_page.dart';
import 'package:photos_repository/photos_repository.dart';
import 'package:user_repository/user_repository.dart';

class App extends StatefulWidget {
  const App({
    required this.photosRepository,
    required this.userRepository,
    super.key,
  });

  final PhotosRepository photosRepository;
  final UserRepository userRepository;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  NavigatorState get _navigator => _navigatorKey.currentState!;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.photosRepository),
        RepositoryProvider.value(value: widget.userRepository),
      ],
      child: BlocProvider(
        create: (context) => AuthenticationBloc(context.read<UserRepository>()),
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          builder: (context, child) {
            return BlocListener<AuthenticationBloc, AuthenticationState>(
              listener: (context, state) {
                if (state is AuthenticationAuthenticated) {
                  _navigator.pushAndRemoveUntil<void>(
                    PhotosPage.route(),
                    (_) => false,
                  );
                } else if (state is AuthenticationUnauthenticated) {
                  _navigator.pushAndRemoveUntil<void>(
                    LoginPage.route(),
                    (_) => false,
                  );
                }
              },
              child: child,
            );
          },
          onGenerateRoute: (settings) {
            if (settings.name == Navigator.defaultRouteName) {
              return SplashPage.route();
            }
            return null;
          },
        ),
      ),
    );
  }
}
