@echo off
REM ─────────────────────────────────────────────────────────────────────────
REM PDF Editor — Windows Local Build Script
REM Usage: build_local.bat [android|windows|all|clean]
REM ─────────────────────────────────────────────────────────────────────────
setlocal

SET TARGET=%1
IF "%TARGET%"=="" SET TARGET=windows

WHERE flutter >nul 2>&1 || (echo ERROR: Flutter not found. Install from https://flutter.dev && exit /b 1)
WHERE java    >nul 2>&1 || (echo ERROR: Java not found. Install JDK 17. && exit /b 1)

echo [INFO] Flutter version:
flutter --version

echo [INFO] Getting dependencies...
flutter pub get || exit /b 1

echo [INFO] Running code generation...
dart run build_runner build --delete-conflicting-outputs || exit /b 1

echo [INFO] Analyzing code...
flutter analyze --no-fatal-infos || exit /b 1

echo [INFO] Running tests...
flutter test || exit /b 1

IF "%TARGET%"=="android" GOTO :android
IF "%TARGET%"=="windows" GOTO :windows
IF "%TARGET%"=="all"     GOTO :all
IF "%TARGET%"=="clean"   GOTO :clean
echo ERROR: Unknown target '%TARGET%'. Use: android, windows, all, clean
exit /b 1

:android
echo [INFO] Building Android APK...
flutter build apk --release --split-per-abi || exit /b 1
echo [OK] APK -> build\app\outputs\flutter-apk\
flutter build appbundle --release || exit /b 1
echo [OK] AAB -> build\app\outputs\bundle\release\
GOTO :done

:windows
echo [INFO] Enabling Windows desktop...
flutter config --enable-windows-desktop || exit /b 1
echo [INFO] Building Windows EXE...
flutter build windows --release || exit /b 1
echo [OK] EXE -> build\windows\x64\runner\Release\
GOTO :done

:all
CALL :android
CALL :windows
GOTO :done

:clean
echo [INFO] Cleaning...
flutter clean
flutter pub get
echo [OK] Clean done.
GOTO :done

:done
echo.
echo [OK] Build complete!
