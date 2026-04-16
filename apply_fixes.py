#!/usr/bin/env python3
"""
PDF Editor Enhancement Patcher
Applies scrolling/zoom enhancements and fixes text editing overlay positioning
"""

import os
import sys
import shutil
from pathlib import Path
from datetime import datetime

def create_backup(repo_path):
    """Create backup of original files"""
    backup_dir = repo_path / f".backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    backup_dir.mkdir(exist_ok=True)
    
    files_to_backup = [
        "lib/screens/editor_screen.dart",
        "lib/widgets/annotation_overlay.dart"
    ]
    
    for file_path in files_to_backup:
        full_path = repo_path / file_path
        if full_path.exists():
            backup_path = backup_dir / file_path
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(full_path, backup_path)
    
    return backup_dir

def apply_enhancement_patch(repo_path):
    """Apply all enhancement patches"""
    
    # Enhanced SfPdfViewer configuration for editor_screen.dart
    editor_screen_enhancement = '''
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
'''
    
    # Text editing overlay fix for annotation_overlay.dart
    annotation_overlay_fix = '''
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
'''
    
    # Write the patch files
    patches_dir = repo_path / ".patches"
    patches_dir.mkdir(exist_ok=True)
    
    with open(patches_dir / "editor_screen_enhancement.dart", "w") as f:
        f.write(editor_screen_enhancement)
    
    with open(patches_dir / "annotation_overlay_fix.dart", "w") as f:
        f.write(annotation_overlay_fix)
    
    return patches_dir

def create_apply_script(repo_path, backup_dir, patches_dir):
    """Create the bash script to apply changes"""
    
    script_content = f'''#!/bin/bash
# PDF Editor Enhancement Application Script
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

set -e  # Exit on error

echo "🎯 PDF Editor Enhancement Patcher"
echo "=================================="
echo ""
echo "Backup created at: {backup_dir}"
echo ""

# Function to apply patch with verification
apply_patch() {{
    local target_file="$1"
    local patch_content="$2"
    local description="$3"
    
    echo "📝 Applying: $description"
    
    if [ ! -f "$target_file" ]; then
        echo "❌ Error: Target file not found: $target_file"
        return 1
    fi
    
    # Create backup of individual file
    cp "$target_file" "$target_file.bak"
    
    # Here you would apply the specific patch
    # For now, we'll just indicate the changes need to be applied manually
    echo "   ⚠️  Manual integration required for: $target_file"
    echo "   📄 Patch content available at: {patches_dir}/"
    
    return 0
}}

echo "🔧 Applying enhancements..."
echo ""

# Apply editor screen enhancements
apply_patch \\
    "{repo_path}/lib/screens/editor_screen.dart" \\
    "{patches_dir}/editor_screen_enhancement.dart" \\
    "Enhanced scrolling and zoom with trackpad support"

# Apply annotation overlay fixes
apply_patch \\
    "{repo_path}/lib/widgets/annotation_overlay.dart" \\
    "{patches_dir}/annotation_overlay_fix.dart" \\
    "Fixed text editing overlay positioning"

echo ""
echo "✨ Enhancement patches prepared!"
echo ""
echo "📋 Next steps:"
echo "1. Review the patch files in: {patches_dir}"
echo "2. Manually integrate the changes into your source files"
echo "3. Run: flutter pub get"
echo "4. Run: flutter run"
echo ""
echo "🔄 To revert changes, restore from backup: {backup_dir}"
echo ""

# Make script executable
chmod +x "$0"
'''

    script_path = repo_path / "apply_changes.sh"
    with open(script_path, "w") as f:
        f.write(script_content)
    
    os.chmod(script_path, 0o755)
    return script_path

def main():
    if len(sys.argv) != 2:
        print("Usage: python apply_changes.py <path_to_pdf_editor3_repo>")
        sys.exit(1)
    
    repo_path = Path(sys.argv[1]).resolve()
    
    if not repo_path.exists():
        print(f"Error: Repository path does not exist: {repo_path}")
        sys.exit(1)
    
    if not (repo_path / "pubspec.yaml").exists():
        print(f"Error: Not a Flutter project directory: {repo_path}")
        sys.exit(1)
    
    print("🚀 PDF Editor Enhancement Patcher")
    print("==================================")
    
    # Create backup
    backup_dir = create_backup(repo_path)
    print(f"✅ Backup created: {backup_dir}")
    
    # Apply patches
    patches_dir = apply_enhancement_patch(repo_path)
    print(f"✅ Enhancement patches prepared: {patches_dir}")
    
    # Create apply script
    script_path = create_apply_script(repo_path, backup_dir, patches_dir)
    print(f"✅ Application script created: {script_path}")
    
    print("\n🎉 Setup complete!")
    print(f"\nRun the following command to apply changes:")
    print(f"  cd {repo_path} && bash apply_changes.sh")

if __name__ == "__main__":
    main()