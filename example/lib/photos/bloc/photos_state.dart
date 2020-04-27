part of 'photos_bloc.dart';

abstract class PhotosState extends Equatable {
  const PhotosState();

  @override
  List<Object> get props => [];

  @override
  bool get stringify => true;
}

class PhotosLoadInProgress extends PhotosState {}

class PhotosLoadFailure extends PhotosState {}

class PhotosLoadSuccess extends PhotosState {
  PhotosLoadSuccess(this.photos, {DateTime lastUpdated})
      : lastUpdated = lastUpdated ?? DateTime.now();

  final List<String> photos;
  final DateTime lastUpdated;

  @override
  List<Object> get props => [photos];
}
