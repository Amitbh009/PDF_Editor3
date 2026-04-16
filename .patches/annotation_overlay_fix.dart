
  // FIXED: Text editing overlay positioning
  Widget _buildTextAnnotationWidget(TextAnnotation annotation) {
    final pdfPagePosition = _getPdfPagePosition(annotation);
    
    return Positioned(
      left: pdfPagePosition.dx,
      top: pdfPagePosition.dy,
      child: GestureDetector(
        onTap: () => _startTextEditing(annotation),
        child: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withOpacity(0.95),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(2, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                annotation.text,
                style: TextStyle(
                  fontSize: annotation.fontSize,
                  fontWeight: annotation.isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: annotation.isItalic ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              if (_editingTextId == annotation.id)
                _buildTextEditingControls(annotation),
            ],
          ),
        ),
      ),
    );
  }

  Offset _getPdfPagePosition(TextAnnotation annotation) {
    try {
      final screenPoint = _pdfViewerController.convertPdfPointToScreenPoint(
        annotation.position,
        annotation.pageNumber,
      );
      return screenPoint;
    } catch (e) {
      print('Error calculating PDF position: $e');
      return Offset(annotation.position.dx, annotation.position.dy);
    }
  }
