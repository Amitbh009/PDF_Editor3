
  // ENHANCED: PDF Viewer with scrolling and zoom enhancements
  Widget _buildPdfViewer() {
    return SfPdfViewer.file(
      widget.pdfFile,
      controller: _pdfViewerController,
      scrollDirection: PdfScrollDirection.vertical,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      enableDocumentLinkAnnotation: true,
      interactionMode: _currentTool == PdfEditTool.text 
          ? PdfInteractionMode.pan 
          : PdfInteractionMode.selection,
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        setState(() {
          _totalPages = details.document.pages.count;
        });
      },
      // Enhanced zoom configuration for trackpad and mouse wheel
      maxZoomLevel: 4.0,
      minZoomLevel: 0.5,
      zoomEnabled: true,
      // Scroll bar styling
      scrollHeadStyle: PdfScrollHeadStyle(
        backgroundColor: Colors.grey.withOpacity(0.8),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      // Trackpad gesture support
      onPdfTap: (PdfTapDetails details) {
        if (_currentTool == PdfEditTool.text) {
          _addTextAnnotationAt(details.position, details.pageNumber);
        }
      },
    );
  }
