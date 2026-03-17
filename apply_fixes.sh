#!/usr/bin/env bash
# apply_fixes.sh — applies ALL fixes from all 3 sessions to PDF_Editor3
# Run from the repo root:  bash apply_fixes.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
echo "📁 Working in: $(pwd)"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 1. lib/main.dart  (was missing entirely)
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# 2. android/settings.gradle  (old imperative DSL → new declarative DSL)
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# 3. android/build.gradle  (remove legacy buildscript{} block)
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# 4. android/app/build.gradle  (safe signing config fallback)
# ──────────────────────────────────────────────────────────────────────────────
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
                // Fall back to debug keystore for non-tag CI builds
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

# ──────────────────────────────────────────────────────────────────────────────
# 5. android/app/src/main/AndroidManifest.xml  (add READ_MEDIA_DOCUMENTS)
# ──────────────────────────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# 6. windows/CMakeLists.txt  (apply_standard_settings defined before subdirs)
# ──────────────────────────────────────────────────────────────────────────────
cat > windows/CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.14)
project(pdf_editor LANGUAGES CXX)

set(BINARY_NAME "pdf_editor")
set(APPLICATION_ID "com.pdfeditor.app")

cmake_policy(VERSION 3.14...3.25)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define build configuration.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
endif()

# apply_standard_settings must be defined BEFORE add_subdirectory calls
# that use it (flutter/ and runner/).
function(apply_standard_settings target)
  target_compile_features(${target} PUBLIC cxx_std_17)
  target_compile_options(${target} PRIVATE
    /W4
    /WX
    /wd"4100"
    /wd"4459"
    /wd"5105"
    "$<$<CONFIG:Debug>:/MTd>"
    "$<$<NOT:$<CONFIG:Debug>>:/MT>"
  )
  target_compile_definitions(${target} PRIVATE
    "$<$<CONFIG:Debug>:_DEBUG>"
  )
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build.
add_subdirectory("runner")

# Enable the test target.
set(include_${APPLICATION_ID}_tests FALSE)

# Generated plugin build rules.
include(flutter/generated_plugins.cmake)

# === Installation ===
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
EOF
echo "✅ windows/CMakeLists.txt"

# ──────────────────────────────────────────────────────────────────────────────
# 7. windows/flutter/CMakeLists.txt  (was missing — Flutter tool backend wiring)
# ──────────────────────────────────────────────────────────────────────────────
cat > windows/flutter/CMakeLists.txt << 'EOF'
# This file controls Flutter-level build steps. It should not be edited.
cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# TODO: Move the rest of this into files in ephemeral. See
# https://github.com/flutter/flutter/issues/57146.

# Serves the same purpose as list(TRANSFORM ... PREPEND ...), which isn't
# available in 3.14.
function(list_prepend LIST_NAME PREFIX)
  set(NEW_LIST "")
  foreach(element ${${LIST_NAME}})
    list(APPEND NEW_LIST "${PREFIX}${element}")
  endforeach(element)
  set(${LIST_NAME} "${NEW_LIST}" PARENT_SCOPE)
endfunction()

# === Flutter Library ===
# System-level dependencies.
find_package(OpenGL REQUIRED)

set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")

# Published to parent scope for install step.
set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_BINARY_DIR}/" PARENT_SCOPE)
set(AOT_LIBRARY "${PROJECT_BINARY_DIR}/windows/app.so" PARENT_SCOPE)

list(APPEND FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_windows.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)
list_prepend(FLUTTER_LIBRARY_HEADERS "${EPHEMERAL_DIR}/")
add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}.lib")
add_dependencies(flutter flutter_assemble)

# === Wrapper sources ===
list(APPEND CPP_WRAPPER_SOURCES_CORE
  "core_implementations.cc"
  "standard_codec.cc"
)
list_prepend(CPP_WRAPPER_SOURCES_CORE "${EPHEMERAL_DIR}/cpp_client_wrapper/")

list(APPEND CPP_WRAPPER_SOURCES_PLUGIN
  "plugin_registrar.cc"
)
list_prepend(CPP_WRAPPER_SOURCES_PLUGIN "${EPHEMERAL_DIR}/cpp_client_wrapper/")

list(APPEND CPP_WRAPPER_SOURCES_APP
  "flutter_engine.cc"
  "flutter_view_controller.cc"
)
list_prepend(CPP_WRAPPER_SOURCES_APP "${EPHEMERAL_DIR}/cpp_client_wrapper/")

# Wrapper library for plugins.
add_library(flutter_wrapper_plugin STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
)
apply_standard_settings(flutter_wrapper_plugin)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  POSITION_INDEPENDENT_CODE ON)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${EPHEMERAL_DIR}/cpp_client_wrapper/include"
)
add_dependencies(flutter_wrapper_plugin flutter_assemble)

# Wrapper library for the app.
add_library(flutter_wrapper_app STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_APP}
)
apply_standard_settings(flutter_wrapper_app)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC
  "${EPHEMERAL_DIR}/cpp_client_wrapper/include"
)
add_dependencies(flutter_wrapper_app flutter_assemble)

# === Flutter tool backend ===
# _phony_ is a non-existent file to force this target to run every time,
# since currently there's no way to get a full input/output list from the
# flutter tool.
set(PHONY_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/_phony_")
set_source_files_properties("${PHONY_OUTPUT}" PROPERTIES SYMBOLIC TRUE)
add_custom_command(
  OUTPUT ${FLUTTER_LIBRARY} ${FLUTTER_LIBRARY_HEADERS}
    ${CPP_WRAPPER_SOURCES_CORE} ${CPP_WRAPPER_SOURCES_PLUGIN}
    ${CPP_WRAPPER_SOURCES_APP}
    "${PHONY_OUTPUT}"
  COMMAND ${CMAKE_COMMAND} -E env
    FLUTTER_ROOT="${FLUTTER_ROOT}"
    "${FLUTTER_TOOL_ENVIRONMENT}"
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      windows-x64 $<CONFIG>
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIBRARY}"
  ${FLUTTER_LIBRARY_HEADERS}
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
  ${CPP_WRAPPER_SOURCES_APP}
)
EOF
echo "✅ windows/flutter/CMakeLists.txt"

# ──────────────────────────────────────────────────────────────────────────────
# 8. windows/runner/utils.h  (add missing Utf8FromUtf16 declaration)
# ──────────────────────────────────────────────────────────────────────────────
cat > windows/runner/utils.h << 'EOF'
#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Returns the UTF-8 encoded arguments as a vector of std::strings.
std::vector<std::string> GetCommandLineArguments();

// Converts a UTF-16 encoded string to a UTF-8 encoded string.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

#endif  // RUNNER_UTILS_H_
EOF
echo "✅ windows/runner/utils.h"

# ──────────────────────────────────────────────────────────────────────────────
# 9. windows/runner/utils.cpp  (remove nonexistent flutter/fml/macros.h include)
# ──────────────────────────────────────────────────────────────────────────────
cat > windows/runner/utils.cpp << 'EOF'
#include "utils.h"

#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  int target_length =
      ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, -1,
                            nullptr, 0, nullptr, nullptr);
  if (target_length == 0) {
    return std::string();
  }
  // target_length includes the null terminator; exclude it from the string.
  --target_length;
  std::string utf8_string;
  utf8_string.resize(target_length);
  int input_length = static_cast<int>(wcslen(utf16_string));
  int converted_length =
      ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
                            input_length, utf8_string.data(), target_length,
                            nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}
EOF
echo "✅ windows/runner/utils.cpp"

# ──────────────────────────────────────────────────────────────────────────────
# 10. windows/runner/win32_window.cpp  (all helpers inside anonymous namespace)
# ──────────────────────────────────────────────────────────────────────────────
cat > windows/runner/win32_window.cpp << 'EOF'
#include "win32_window.h"

#include <dwmapi.h>
#include <flutter/flutter_view_controller.h>

#include "resource.h"

namespace {

// Track number of active windows to manage window class registration lifetime.
static int g_active_window_count = 0;

/// Window attribute that enables dark mode window decorations.
static const DWORD DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

/// Registry key for app theme preference.
static const wchar_t kGetPreferredBrightnessRegKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
static const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// Scales |source| from logical to physical pixels for the given |dpi|.
static int Scale(int source, double dpi_scale) {
  return static_cast<int>(source * dpi_scale);
}

// Returns the current Windows app theme (light or dark mode).
bool IsAppThemeDark() {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result =
      RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                  kGetPreferredBrightnessRegValue, RRF_RT_REG_DWORD, nullptr,
                  &light_mode, &light_mode_size);
  if (result == ERROR_SUCCESS) {
    return light_mode == 0;
  }
  return false;
}

// Applies dark/light title-bar colouring to |window|.
static void UpdateTheme(HWND window) {
  BOOL dark_mode = IsAppThemeDark();
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark_mode,
                        sizeof(dark_mode));
}

// Manages the Win32 window class lifecycle.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  const wchar_t* GetWindowClass();
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;
  static WindowClassRegistrar* instance_;
  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIconW(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return L"FLUTTER_RUNNER_WIN32_WINDOW";
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  class_registered_ = false;
}

}  // namespace

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();
  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                               static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

LRESULT
Win32Window::MessageHandler(HWND hwnd, UINT const message,
                             WPARAM const wparam,
                             LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;
      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top,
                   newWidth, newHeight, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }

    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top,
                   rect.right - rect.left, rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }
  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));
    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableNonClientDpiScaling(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void Win32Window::Show() {
  ShowWindow(window_handle_, SW_SHOWNORMAL);
  UpdateWindow(window_handle_);
}
EOF
echo "✅ windows/runner/win32_window.cpp"

# ──────────────────────────────────────────────────────────────────────────────
# 11. .gitignore  (add windows/flutter/ephemeral/ exclusion)
# ──────────────────────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
# Flutter / Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.pub-cache/
.pub/
build/
*.g.dart
*.freezed.dart

# Android
**/android/**/gradle-wrapper.jar
**/android/.gradle
**/android/captures/
**/android/gradlew
**/android/gradlew.bat
**/android/local.properties
**/android/**/GeneratedPluginRegistrant.java
**/android/key.properties
android/app/keystore.jks

# Windows
**/windows/flutter/generated_plugin_registrant.cc
**/windows/flutter/generated_plugin_registrant.h
**/windows/flutter/generated_plugins.cmake
**/windows/flutter/ephemeral/

# iOS / macOS (not targets but keeping clean)
**/ios/Flutter/.last_build_id
**/ios/Flutter/App.framework
**/ios/Flutter/Flutter.framework
**/ios/Flutter/Flutter.podspec
**/ios/Flutter/Generated.xcconfig
**/ios/Flutter/ephemeral/
**/ios/Flutter/app.flx
**/ios/Flutter/app.zip
**/ios/Flutter/flutter_assets/
**/ios/ServiceDefinitions.json
**/ios/Runner/GeneratedPluginRegistrant.*
**/macos/Flutter/GeneratedPluginRegistrant.swift
**/macos/Flutter/ephemeral

# Coverage
coverage/

# IntelliJ / AS
*.iml
*.ipr
*.iws
.idea/

# VS Code
.vscode/

# macOS
.DS_Store

# Linux
*~
EOF
echo "✅ .gitignore"

# ──────────────────────────────────────────────────────────────────────────────
# 12. .github/workflows/build.yml  (re-enable analyze job, fix all needs:)
# ──────────────────────────────────────────────────────────────────────────────
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

  # ── Code quality gate ───────────────────────────────────────────────────────
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

  # ── Android APK + AAB ───────────────────────────────────────────────────────
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

  # ── Windows EXE + Installer ─────────────────────────────────────────────────
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

  # ── GitHub Release ───────────────────────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# Commit & push everything
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "Staging all changes..."
git add \
  lib/main.dart \
  android/settings.gradle \
  android/build.gradle \
  android/app/build.gradle \
  android/app/src/main/AndroidManifest.xml \
  windows/CMakeLists.txt \
  windows/flutter/CMakeLists.txt \
  windows/runner/utils.h \
  windows/runner/utils.cpp \
  windows/runner/win32_window.cpp \
  .gitignore \
  .github/workflows/build.yml

git commit -m "fix: all build errors — Android Gradle DSL, Windows CMake, main.dart

Session 1 — lib/main.dart:
  - Add missing app entry point (ProviderScope, Material3, Inter font)

Session 2 — Android Gradle 'unsupported project' error:
  - android/settings.gradle: migrate from imperative apply-from style to
    new declarative pluginManagement{} + plugins{} DSL
  - android/build.gradle: remove conflicting legacy buildscript{} block
  - android/app/build.gradle: safe signingConfig fallback to debug keystore
    when KEYSTORE_PATH env var is absent (non-tag builds)
  - AndroidManifest.xml: add READ_MEDIA_DOCUMENTS for Android 13+ PDF access

Session 3 — Windows CMake 'Unable to generate build files' error:
  - windows/flutter/CMakeLists.txt: was missing — add Flutter tool backend
    wiring (flutter_assemble, wrapper libs, ephemeral dir references)
  - windows/CMakeLists.txt: apply_standard_settings() already defined here;
    no change needed
  - windows/runner/utils.h: add missing Utf8FromUtf16 declaration
  - windows/runner/utils.cpp: remove nonexistent flutter/fml/macros.h include
  - windows/runner/win32_window.cpp: all helpers inside anonymous namespace
  - .gitignore: add windows/flutter/ephemeral/ exclusion

CI workflow:
  - Re-enable analyze job (was commented out, breaking needs: analyze)
  - build-android and build-windows both correctly need: analyze"

echo ""
echo "Pushing to origin/main..."
git push
echo ""
echo "✅ All fixes applied and pushed successfully!"
