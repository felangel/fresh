part of 'photos_bloc.dart';

abstract class PhotosEvent extends Equatable {
  @override
  List<Object> get props => [];

  @override
  bool get stringify => true;
}

class PhotosRequested extends PhotosEvent {}
