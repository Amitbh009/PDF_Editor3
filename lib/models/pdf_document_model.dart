import 'package:freezed_annotation/freezed_annotation.dart';
import 'annotation_model.dart';

part 'pdf_document_model.freezed.dart';
part 'pdf_document_model.g.dart';

@freezed
class PdfDocumentModel with _$PdfDocumentModel {
  const factory PdfDocumentModel({
    required String id,
    required String filePath,
    required String fileName,
    required int totalPages,
    @Default(1) int currentPage,
    @Default([]) List<AnnotationModel> annotations,
    @Default(false) bool isModified,
    DateTime? lastModified,
  }) = _PdfDocumentModel;

  factory PdfDocumentModel.fromJson(Map<String, dynamic> json) =>
      _$PdfDocumentModelFromJson(json);
}
