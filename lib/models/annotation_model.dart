import 'package:freezed_annotation/freezed_annotation.dart';

part 'annotation_model.freezed.dart';
part 'annotation_model.g.dart';

enum AnnotationType {
  text,
  highlight,
  underline,
  strikethrough,
  freehand,
  rectangle,
  circle,
  arrow,
  stamp,
  image,
}

@freezed
class AnnotationModel with _$AnnotationModel {
  const factory AnnotationModel({
    required String id,
    required AnnotationType type,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
    required double height,
    @Default('') String content,
    @Default(0xFF000000) int color,
    @Default(1.0) double strokeWidth,
    @Default(1.0) double opacity,
    @Default(14.0) double fontSize,
    @Default('Inter') String fontFamily,
    @Default(false) bool isBold,
    @Default(false) bool isItalic,
    List<Map<String, double>>? pathPoints,
    DateTime? createdAt,
  }) = _AnnotationModel;

  factory AnnotationModel.fromJson(Map<String, dynamic> json) =>
      _$AnnotationModelFromJson(json);
}
