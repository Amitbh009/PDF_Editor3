# PDF Editor

A production-grade, cross-platform PDF editor built with Flutter.
Edit PDFs on **Android** and **Windows** — annotate, highlight, draw, add text, and export.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📝 Text annotations | Tap anywhere to add text with bold/italic/font size |
| 🖍 Highlight | Drag to highlight any area in any colour |
| ✏️ Underline / Strikethrough | Mark up text selections |
| 🎨 Freehand drawing | Draw with your finger or mouse |
| 🔲 Shapes | Rectangle and circle shapes |
| 🗑 Eraser | Remove individual annotations |
| 🔍 Zoom | Pinch-to-zoom or toolbar controls |
| 📄 Page thumbnails | Collapsible left panel |
| 🗂 Annotations list | See & delete all annotations |
| 💾 Save to PDF | Annotations burned into the PDF file |
| 📤 Share | Share via system share sheet |
| 🌙 Dark mode | Full Material 3 light/dark theme |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter 3.27.4+](https://flutter.dev/docs/get-started/install)
- Java 17 (for Android builds)
- Android Studio / VS Code with Flutter extension

### Installation

```bash
git clone https://github.com/your-org/pdf_editor.git
cd pdf_editor

# Install dependencies
flutter pub get

# Generate Freezed / Riverpod code
dart run build_runner build --delete-conflicting-outputs
```

### Running

```bash
# Android (device/emulator)
flutter run

# Windows desktop
flutter config --enable-windows-desktop
flutter run -d windows
```

---

## 🏗 Building

### Android APK

```bash
flutter build apk --release --split-per-abi
# → build/app/outputs/flutter-apk/
```

### Android App Bundle (Google Play)

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

### Windows EXE

```bash
flutter config --enable-windows-desktop
flutter build windows --release
# → build/windows/x64/runner/Release/
```

---

## 🔐 Release Signing (Android)

1. Generate a keystore:
```bash
keytool -genkey -v -keystore pdf-editor.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias pdf-editor
```

2. Set GitHub repository secrets:

| Secret | Value |
|--------|-------|
| `KEYSTORE_BASE64` | `base64 -w0 pdf-editor.jks` |
| `KEYSTORE_PASSWORD` | Your keystore password |
| `KEY_ALIAS` | `pdf-editor` |
| `KEY_PASSWORD` | Your key password |

3. Push a version tag to trigger a signed release:
```bash
git tag v1.0.0
git push --tags
```

---

## 🔄 CI/CD

GitHub Actions workflow (`.github/workflows/build.yml`):

```
push / PR
   └── Analyze & Test
         ├── Android APK + AAB  (ubuntu-latest)
         └── Windows EXE + NSIS installer  (windows-latest)
               └── [on tag] → GitHub Release with all artifacts
```

---

## 📂 Project Structure

```
lib/
├── main.dart                   # App entry point
├── models/
│   ├── annotation_model.dart   # Freezed annotation data model
│   └── pdf_document_model.dart # Freezed document state model
├── providers/
│   └── pdf_provider.dart       # Riverpod state management
├── screens/
│   ├── home_screen.dart        # File picker & welcome screen
│   └── editor_screen.dart      # Main editor screen
├── services/
│   └── pdf_service.dart        # Syncfusion PDF read/write
└── widgets/
    ├── annotation_overlay.dart # CustomPainter + gesture detection
    ├── annotations_list.dart   # Collapsible annotation list panel
    ├── editor_toolbar.dart     # Tool selection toolbar
    ├── page_navigator.dart     # Bottom page nav bar
    ├── properties_panel.dart   # Right-side properties panel
    └── thumbnail_panel.dart    # Left-side page thumbnails
```

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `syncfusion_flutter_pdfviewer` | PDF rendering |
| `syncfusion_flutter_pdf` | PDF modification & annotation writing |
| `flutter_riverpod` | State management |
| `freezed` | Immutable data models |
| `file_picker` | File browser (Android + Windows) |
| `flutter_colorpicker` | Color picker dialog |
| `google_fonts` | Inter font |
| `share_plus` | Native share sheet |
| `path_provider` | App documents directory |

> **Note:** Syncfusion packages require a free community licence for apps with < $1M annual revenue.
> Register at [syncfusion.com/products/communitylicense](https://www.syncfusion.com/products/communitylicense)
> and initialize before use if required by the package version.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## 📄 Licence

MIT © 2025 PDF Editor Team
