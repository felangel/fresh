import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fresh_example/app/app.dart';
import 'package:fresh_example/simple_bloc_observer.dart';
import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';
import 'package:photos_repository/photos_repository.dart';
import 'package:user_repository/user_repository.dart';

void main() {
  Bloc.observer = SimpleBlocObserver();

  final jsonplaceholderClient = JsonplaceholderClient();
  final photosRepository = PhotosRepository(jsonplaceholderClient);
  final userRepository = UserRepository(jsonplaceholderClient);

  runApp(
    App(
      photosRepository: photosRepository,
      userRepository: userRepository,
    ),
  );
}
