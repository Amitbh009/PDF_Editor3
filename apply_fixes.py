#!/usr/bin/env python3
"""
PDF Editor Enhancement Patcher - Direct File Modifier
Run this script to automatically apply:
1. Scrolling + zoom with trackpad/mouse wheel + Ctrl
2. Text edit boxes positioned directly over the text
"""

import re
import sys
from pathlib import Path
from datetime import datetime
import shutil

# ----------------------------------------------------------------------
# 1. Enhanced Scrolling & Zoom (editor_screen.dart)
# ----------------------------------------------------------------------
def patch_editor_screen(file_path: Path):
    """Replace the SfPdfViewer widget with enhanced version."""
    content = file_path.read_text(encoding='utf-8')
    backup = file_path.with_suffix('.dart.bak')
    shutil.copy2(file_path, backup)

    # Find the SfPdfViewer.file widget definition and replace it
    # Pattern looks for 'SfPdfViewer.file(' and captures until the matching closing parenthesis
    # We'll use a simpler approach: replace the entire _buildPdfViewer method
    # if it exists, otherwise insert a new one.

    # Check if _buildPdfViewer method exists
    if '_buildPdfViewer' not in content:
        # If not found, we'll add the method after _buildBody or similar
        # For simplicity, we'll add it before the build method's return
        print("⚠️  _buildPdfViewer method not found. Adding new method.")
        insert_pos = content.find('Widget build(BuildContext context) {')
        if insert_pos == -1:
            print("❌ Could not find build method. Aborting editor_screen patch.")
            return False

        new_method = '''
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
      maxZoomLevel: 4.0,
      minZoomLevel: 0.5,
      zoomEnabled: true,
      scrollHeadStyle: PdfScrollHeadStyle(
        backgroundColor: Colors.grey.withOpacity(0.8),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      onPdfTap: (PdfTapDetails details) {
        if (_currentTool == PdfEditTool.text) {
          _addTextAnnotationAt(details.position, details.pageNumber);
        }
      },
    );
  }
'''
        # Insert before the closing brace of build method
        # Find the line with 'return' and insert before it
        lines = content.split('\n')
        new_lines = []
        inserted = False
        for i, line in enumerate(lines):
            if not inserted and 'return' in line and 'Scaffold' in line:
                # Add method before return
                new_lines.append(new_method)
                inserted = True
            new_lines.append(line)
        if not inserted:
            # Fallback: add at end of class
            class_end = content.rfind('}')
            new_content = content[:class_end] + new_method + '\n' + content[class_end:]
        else:
            new_content = '\n'.join(new_lines)
        file_path.write_text(new_content, encoding='utf-8')
        print("✅ Added enhanced _buildPdfViewer method.")
        return True

    # If method exists, replace its body with enhanced version
    print("🔧 Updating existing _buildPdfViewer method...")
    pattern = r'(Widget\s+_buildPdfViewer\s*\(\s*\)\s*\{)(.*?)(\n\s*\})'
    replacement = r'''\1
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
      maxZoomLevel: 4.0,
      minZoomLevel: 0.5,
      zoomEnabled: true,
      scrollHeadStyle: PdfScrollHeadStyle(
        backgroundColor: Colors.grey.withOpacity(0.8),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      onPdfTap: (PdfTapDetails details) {
        if (_currentTool == PdfEditTool.text) {
          _addTextAnnotationAt(details.position, details.pageNumber);
        }
      },
    );
  \3'''
    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    if new_content == content:
        print("⚠️  Could not find _buildPdfViewer method pattern. No changes made.")
        return False
    file_path.write_text(new_content, encoding='utf-8')
    print("✅ Enhanced _buildPdfViewer with scrolling and zoom features.")
    return True


# ----------------------------------------------------------------------
# 2. Fix Text Editing Overlay Positioning (annotation_overlay.dart)
# ----------------------------------------------------------------------
def patch_annotation_overlay(file_path: Path):
    """Replace _buildTextAnnotationWidget and add helper method."""
    content = file_path.read_text(encoding='utf-8')
    backup = file_path.with_suffix('.dart.bak')
    shutil.copy2(file_path, backup)

    # Replacement for _buildTextAnnotationWidget
    new_widget_method = '''  Widget _buildTextAnnotationWidget(TextAnnotation annotation) {
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
  }'''

    # Helper method to calculate position
    helper_method = '''  Offset _getPdfPagePosition(TextAnnotation annotation) {
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
  }'''

    # Replace _buildTextAnnotationWidget method
    pattern = r'(Widget\s+_buildTextAnnotationWidget\s*\(.*?\)\s*\{)(.*?)(\n\s*\})'
    if re.search(pattern, content, flags=re.DOTALL):
        new_content = re.sub(pattern, new_widget_method, content, flags=re.DOTALL)
        print("✅ Replaced _buildTextAnnotationWidget with overlay positioning fix.")
    else:
        print("⚠️  _buildTextAnnotationWidget method not found. Adding new method.")
        # Insert before the closing brace of the class
        class_end = content.rfind('}')
        if class_end == -1:
            print("❌ Could not find class end.")
            return False
        new_content = content[:class_end] + '\n' + new_widget_method + '\n' + helper_method + '\n' + content[class_end:]

    # Add helper method if not already present
    if '_getPdfPagePosition' not in new_content:
        # Insert after _buildTextAnnotationWidget
        insert_pos = new_content.find('Widget _buildTextAnnotationWidget')
        if insert_pos != -1:
            method_end = new_content.find('}\n', insert_pos)
            if method_end != -1:
                new_content = (new_content[:method_end+2] +
                               '\n' + helper_method + '\n' +
                               new_content[method_end+2:])
    else:
        print("ℹ️  _getPdfPagePosition already exists.")

    file_path.write_text(new_content, encoding='utf-8')
    return True


# ----------------------------------------------------------------------
# Main execution
# ----------------------------------------------------------------------
def main():
    repo_root = Path.cwd()
    if not (repo_root / 'pubspec.yaml').exists():
        print("❌ Error: Must run from root of Flutter project (where pubspec.yaml is).")
        sys.exit(1)

    print("🚀 PDF Editor Enhancement Patcher")
    print("==================================")
    print(f"Repository: {repo_root}")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("")

    editor_screen = repo_root / 'lib' / 'screens' / 'editor_screen.dart'
    annotation_overlay = repo_root / 'lib' / 'widgets' / 'annotation_overlay.dart'

    success = True
    if editor_screen.exists():
        success &= patch_editor_screen(editor_screen)
    else:
        print(f"❌ File not found: {editor_screen}")
        success = False

    if annotation_overlay.exists():
        success &= patch_annotation_overlay(annotation_overlay)
    else:
        print(f"❌ File not found: {annotation_overlay}")
        success = False

    print("")
    if success:
        print("✅ All patches applied successfully!")
        print("📁 Backups created with .dart.bak extension.")
        print("👉 Next steps: Run 'flutter pub get' and 'flutter run' to test.")
    else:
        print("❌ Some patches failed. Check error messages above.")
        sys.exit(1)

if __name__ == "__main__":
    main()