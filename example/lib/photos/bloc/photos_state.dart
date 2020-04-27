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
  const PhotosLoadSuccess(this.photos);

  final List<String> photos;

  @override
  List<Object> get props => [photos, lastUpdated];
}
