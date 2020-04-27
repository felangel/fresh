import 'package:json_annotation/json_annotation.dart';

part 'photos_response.g.dart';

@JsonSerializable(createToJson: false)
class Photo {
  const Photo(this.albumId, this.id, this.title, this.url, this.thumbnailUrl);

  factory Photo.fromJson(Map<String, dynamic> json) => _$PhotoFromJson(json);

  final int albumId;
  final int id;
  final String title;
  final String url;
  final String thumbnailUrl;
}
