import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:photos_repository/photos_repository.dart';

part 'photos_event.dart';
part 'photos_state.dart';

class PhotosBloc extends Bloc<PhotosEvent, PhotosState> {
  PhotosBloc(PhotosRepository photosRepository)
      : _photosRepository = photosRepository,
        super(PhotosLoadInProgress()) {
    on<PhotosRequested>(_onPhotosRequested);
  }

  final PhotosRepository _photosRepository;

  Future<void> _onPhotosRequested(
    PhotosRequested event,
    Emitter<PhotosState> emit,
  ) async {
    emit(PhotosLoadInProgress());
    try {
      final photos = await _photosRepository.getPhotos();
      emit(PhotosLoadSuccess(photos));
    } catch (_) {
      emit(PhotosLoadFailure());
    }
  }
}
