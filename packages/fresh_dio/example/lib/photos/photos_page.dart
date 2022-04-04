import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fresh_example/authentication/bloc/authentication_bloc.dart';
import 'package:fresh_example/photos/bloc/photos_bloc.dart';
import 'package:photos_repository/photos_repository.dart';

class PhotosPage extends StatelessWidget {
  const PhotosPage._({Key? key}) : super(key: key);

  static Route route() {
    return MaterialPageRoute<void>(
      builder: (_) => BlocProvider(
        create: (context) => PhotosBloc(context.read<PhotosRepository>())
          ..add(PhotosRequested()),
        child: const PhotosPage._(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: const Photos(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton(
            heroTag: 0,
            child: const Icon(Icons.refresh),
            onPressed: () => context.read<PhotosBloc>().add(PhotosRequested()),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 1,
            child: const Icon(Icons.exit_to_app),
            onPressed: () {
              context.read<AuthenticationBloc>().add(LoggedOut());
            },
          ),
        ],
      ),
    );
  }
}

class Photos extends StatelessWidget {
  const Photos({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PhotosBloc, PhotosState>(
      builder: (context, state) {
        if (state is PhotosLoadInProgress) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PhotosLoadSuccess) {
          return _PhotosGrid(photos: state.photos);
        }
        return const Center(child: Text('Uh oh...something went wrong'));
      },
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({Key? key, required this.photos}) : super(key: key);

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
      ),
      itemBuilder: (context, index) => Image.network(photos[index]),
    );
  }
}
