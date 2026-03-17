#!/usr/bin/env bash
# apply_fixes.sh — run from the root of your PDF_Editor3 repo
# Usage: bash apply_fixes.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
# If run from outside the repo, pass the repo path as $1
if [ "${1:-}" != "" ]; then REPO="$1"; fi
cd "$REPO"
echo "Applying fixes to: $REPO"

# ── 1. android/settings.gradle (new declarative plugin DSL) ────────────────
cat > android/settings.gradle << 'EOF'
pluginManagement {
    def flutterSdkPath = {
        def properties = new Properties()
        file("local.properties").withInputStream { properties.load(it) }
        def flutterSdkPath = properties.getProperty("flutter.sdk")
        assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
        return flutterSdkPath
    }()

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    id "com.android.application" version "8.3.0" apply false
    id "org.jetbrains.kotlin.android" version "1.9.10" apply false
}

include ":app"
EOF
echo "✅ android/settings.gradle"

# ── 2. android/build.gradle (remove old buildscript{} block) ───────────────
cat > android/build.gradle << 'EOF'
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"

subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
EOF
echo "✅ android/build.gradle"

# ── 3. android/app/build.gradle (safe signing config) ──────────────────────
cat > android/app/build.gradle << 'EOF'
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.pdfeditor.app"
    compileSdk 35
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId "com.pdfeditor.app"
        minSdk 23
        targetSdk 35
        versionCode flutter.versionCode
        versionName flutter.versionName
        multiDexEnabled true
    }

    signingConfigs {
        release {
            def keystorePath = System.getenv("KEYSTORE_PATH")
            if (keystorePath) {
                storeFile     file(keystorePath)
                storePassword System.getenv("KEYSTORE_PASSWORD") ?: ""
                keyAlias      System.getenv("KEY_ALIAS")         ?: ""
                keyPassword   System.getenv("KEY_PASSWORD")      ?: ""
            } else {
                storeFile     file("${System.getProperty('user.home')}/.android/debug.keystore")
                storePassword "android"
                keyAlias      "androiddebugkey"
                keyPassword   "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
        }
        debug {
            signingConfig signingConfigs.debug
        }
    }
}

flutter {
    source "../.."
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.10"
    implementation "androidx.multidex:multidex:2.0.1"
}
EOF
echo "✅ android/app/build.gradle"

# ── 4. android/app/src/main/AndroidManifest.xml ────────────────────────────
cat > android/app/src/main/AndroidManifest.xml << 'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_DOCUMENTS"
        tools:ignore="ProtectedPermissions"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"
        tools:ignore="ScopedStorage"/>
    <uses-permission android:name="android.permission.INTERNET"/>

    <application
        android:label="PDF Editor"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:largeHeap="true"
        android:requestLegacyExternalStorage="true"
        android:hardwareAccelerated="true">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">

            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>

            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/pdf"/>
            </intent-filter>
        </activity>

        <meta-data android:name="flutterEmbedding" android:value="2"/>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths"/>
        </provider>
    </application>
</manifest>
EOF
echo "✅ android/app/src/main/AndroidManifest.xml"

# ── 5. lib/main.dart ───────────────────────────────────────────────────────
cat > lib/main.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PdfEditorApp()));
}

class PdfEditorApp extends StatelessWidget {
  const PdfEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Editor',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: brightness).textTheme,
      ),
    );
  }
}
EOF
echo "✅ lib/main.dart"

# ── 6. .github/workflows/build.yml (re-enable analyze job) ─────────────────
cat > .github/workflows/build.yml << 'EOF'
name: Build PDF Editor

on:
  push:
    branches: [main, develop]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]
  workflow_dispatch:

env:
  FLUTTER_VERSION: '3.27.4'
  JAVA_VERSION: '17'

jobs:

  analyze:
    name: 🔍 Analyze & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - name: Get dependencies
        run: flutter pub get
      - name: Generate code (freezed / riverpod)
        run: dart run build_runner build --delete-conflicting-outputs
      - name: Analyze
        run: flutter analyze --no-fatal-infos
      - name: Test
        run: flutter test

  build-android:
    name: 🤖 Android (APK + AAB)
    runs-on: ubuntu-latest
    needs: analyze
    steps:
      - uses: actions/checkout@v4
      - name: Set up Java ${{ env.JAVA_VERSION }}
        uses: actions/setup-java@v4
        with:
          java-version: ${{ env.JAVA_VERSION }}
          distribution: temurin
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - name: Get dependencies
        run: flutter pub get
      - name: Generate code
        run: dart run build_runner build --delete-conflicting-outputs
      - name: Decode keystore
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode \
            > android/app/keystore.jks
          echo "KEYSTORE_PATH=$PWD/android/app/keystore.jks" >> $GITHUB_ENV
          echo "KEYSTORE_PASSWORD=${{ secrets.KEYSTORE_PASSWORD }}" >> $GITHUB_ENV
          echo "KEY_ALIAS=${{ secrets.KEY_ALIAS }}" >> $GITHUB_ENV
          echo "KEY_PASSWORD=${{ secrets.KEY_PASSWORD }}" >> $GITHUB_ENV
      - name: Build Debug APK
        if: "!startsWith(github.ref, 'refs/tags/')"
        run: flutter build apk --debug --split-per-abi
      - name: Build Release APK
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          flutter build apk --release \
            --split-per-abi \
            --obfuscate \
            --split-debug-info=build/debug-info/android/
      - name: Build Release AAB
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          flutter build appbundle --release \
            --obfuscate \
            --split-debug-info=build/debug-info/android/
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: android-apk-${{ github.sha }}
          path: build/app/outputs/flutter-apk/*.apk
          retention-days: 14
      - name: Upload AAB
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/upload-artifact@v4
        with:
          name: android-aab-${{ github.sha }}
          path: build/app/outputs/bundle/release/*.aab
          retention-days: 30
      - name: Upload debug symbols
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/upload-artifact@v4
        with:
          name: android-debug-symbols-${{ github.sha }}
          path: build/debug-info/android/
          retention-days: 90

  build-windows:
    name: 🪟 Windows (EXE + Installer)
    runs-on: windows-latest
    needs: analyze
    steps:
      - uses: actions/checkout@v4
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - name: Enable Windows desktop
        run: flutter config --enable-windows-desktop
      - name: Get dependencies
        run: flutter pub get
      - name: Generate code
        run: dart run build_runner build --delete-conflicting-outputs
      - name: Build Windows release
        run: |
          flutter build windows --release `
            --obfuscate `
            --split-debug-info=build/debug-info/windows/
      - name: Package portable ZIP
        shell: pwsh
        run: |
          $src = "build\windows\x64\runner\Release"
          $dst = "PDFEditor-Windows-Portable"
          New-Item -ItemType Directory -Path $dst -Force
          Copy-Item -Recurse "$src\*" "$dst\"
          Compress-Archive -Path $dst -DestinationPath "PDFEditor-Portable-${{ github.ref_name }}.zip"
      - name: Install NSIS
        if: startsWith(github.ref, 'refs/tags/')
        run: choco install nsis -y --no-progress
      - name: Write NSIS script
        if: startsWith(github.ref, 'refs/tags/')
        shell: pwsh
        run: |
          $version = "${{ github.ref_name }}" -replace '^v', ''
          @"
          !define APP_NAME "PDF Editor"
          !define APP_VERSION "$version"
          !define APP_PUBLISHER "PDF Editor"
          !define APP_URL "https://github.com/${{ github.repository }}"
          !define APP_EXE "pdf_editor.exe"
          !define BUILD_DIR "build\windows\x64\runner\Release"
          !define INST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\PDFEditor"
          Unicode True
          Name "`${APP_NAME} `${APP_VERSION}"
          OutFile "PDFEditor-Setup-`${APP_VERSION}.exe"
          InstallDir "`$PROGRAMFILES64\`${APP_NAME}"
          InstallDirRegKey HKCU "`${INST_KEY}" "InstallLocation"
          RequestExecutionLevel admin
          SetCompressor /SOLID lzma
          !include "MUI2.nsh"
          !insertmacro MUI_PAGE_WELCOME
          !insertmacro MUI_PAGE_DIRECTORY
          !insertmacro MUI_PAGE_INSTFILES
          !insertmacro MUI_PAGE_FINISH
          !insertmacro MUI_UNPAGE_CONFIRM
          !insertmacro MUI_UNPAGE_INSTFILES
          !insertmacro MUI_LANGUAGE "English"
          Section "PDF Editor" SecMain
            SetOutPath "`$INSTDIR"
            File /r "`${BUILD_DIR}\*.*"
            CreateDirectory "`$SMPROGRAMS\`${APP_NAME}"
            CreateShortcut "`$SMPROGRAMS\`${APP_NAME}\`${APP_NAME}.lnk" "`$INSTDIR\`${APP_EXE}"
            CreateShortcut "`$SMPROGRAMS\`${APP_NAME}\Uninstall.lnk" "`$INSTDIR\Uninstall.exe"
            CreateShortcut "`$DESKTOP\`${APP_NAME}.lnk" "`$INSTDIR\`${APP_EXE}"
            WriteRegStr HKCU "`${INST_KEY}" "DisplayName" "`${APP_NAME}"
            WriteRegStr HKCU "`${INST_KEY}" "DisplayVersion" "`${APP_VERSION}"
            WriteRegStr HKCU "`${INST_KEY}" "Publisher" "`${APP_PUBLISHER}"
            WriteRegStr HKCU "`${INST_KEY}" "URLInfoAbout" "`${APP_URL}"
            WriteRegStr HKCU "`${INST_KEY}" "InstallLocation" "`$INSTDIR"
            WriteRegStr HKCU "`${INST_KEY}" "UninstallString" "`$INSTDIR\Uninstall.exe"
            WriteRegDWORD HKCU "`${INST_KEY}" "NoModify" 1
            WriteRegDWORD HKCU "`${INST_KEY}" "NoRepair" 1
            WriteUninstaller "`$INSTDIR\Uninstall.exe"
          SectionEnd
          Section "Uninstall"
            Delete "`$INSTDIR\Uninstall.exe"
            RMDir /r "`$INSTDIR"
            Delete "`$DESKTOP\`${APP_NAME}.lnk"
            RMDir /r "`$SMPROGRAMS\`${APP_NAME}"
            DeleteRegKey HKCU "`${INST_KEY}"
          SectionEnd
          "@ | Out-File -FilePath installer.nsi -Encoding UTF8
      - name: Build installer
        if: startsWith(github.ref, 'refs/tags/')
        run: makensis installer.nsi
      - name: Upload portable ZIP
        uses: actions/upload-artifact@v4
        with:
          name: windows-portable-${{ github.sha }}
          path: PDFEditor-Portable-*.zip
          retention-days: 14
      - name: Upload installer
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/upload-artifact@v4
        with:
          name: windows-installer-${{ github.sha }}
          path: PDFEditor-Setup-*.exe
          retention-days: 30

  release:
    name: 🚀 Publish Release
    runs-on: ubuntu-latest
    needs: [build-android, build-windows]
    if: startsWith(github.ref, 'refs/tags/')
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: dist/
      - name: List artifacts
        run: find dist/ -type f | sort
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: "PDF Editor ${{ github.ref_name }}"
          body: |
            ## 📱 PDF Editor ${{ github.ref_name }}
            A full-featured PDF editor for Android & Windows.
            ### 🔧 Requirements
            - **Android**: 6.0+ (API 23)
            - **Windows**: Windows 10 64-bit or newer
          draft: false
          prerelease: ${{ contains(github.ref_name, '-') }}
          files: |
            dist/**/*.apk
            dist/**/*.aab
            dist/**/*.exe
            dist/**/*.zip
EOF
echo "✅ .github/workflows/build.yml"

# ── Commit and push ──────────────────────────────────────────────────────────
git add android/settings.gradle android/build.gradle android/app/build.gradle \
        android/app/src/main/AndroidManifest.xml lib/main.dart \
        .github/workflows/build.yml

git commit -m "fix: migrate Android Gradle to declarative DSL, add main.dart, fix workflow

- settings.gradle: new pluginManagement{} + plugins{} DSL (fixes 'unsupported Gradle project')
- build.gradle: remove conflicting buildscript{} block
- app/build.gradle: safe signing config fallback for non-tag builds
- AndroidManifest.xml: add READ_MEDIA_DOCUMENTS for Android 13+ PDF access
- lib/main.dart: add missing app entry point
- build.yml: re-enable analyze job (was commented out, breaking needs: analyze)"

git push
echo ""
echo "✅ All fixes committed and pushed successfully."
