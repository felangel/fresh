import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:photos_repository/photos_repository.dart';

part 'photos_event.dart';
part 'photos_state.dart';

class PhotosBloc extends Bloc<PhotosEvent, PhotosState> {
  PhotosBloc(PhotosRepository photosRepository)
      : assert(photosRepository != null),
        _photosRepository = photosRepository;

  final PhotosRepository _photosRepository;

  @override
  PhotosState get initialState => PhotosLoadInProgress();

  @override
  Stream<PhotosState> mapEventToState(
    PhotosEvent event,
  ) async* {
    if (event is PhotosRequested) {
      yield* _mapPhotosRequestedToState();
    }
  }

  Stream<PhotosState> _mapPhotosRequestedToState() async* {
    yield PhotosLoadInProgress();
    try {
      final photos = await _photosRepository.getPhotos();
      yield PhotosLoadSuccess(photos);
    } on Exception catch (_) {
      yield PhotosLoadFailure();
    }
  }
}
