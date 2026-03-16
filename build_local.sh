#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# PDF Editor — Local Build Script
# Usage:
#   ./build_local.sh          → build Android APK (default)
#   ./build_local.sh android  → build APK + AAB
#   ./build_local.sh windows  → build Windows EXE (Windows only)
#   ./build_local.sh all      → build everything available
#   ./build_local.sh clean    → clean build artifacts
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

TARGET="${1:-android}"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PDF Editor Build Script${NC}"
echo -e "${BOLD}  Target: ${YELLOW}${TARGET}${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Check Flutter ──────────────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
  error "Flutter not found!\nInstall from: https://docs.flutter.dev/get-started/install"
fi
info "Flutter version:"
flutter --version

# ── Clean ──────────────────────────────────────────────────────────────────
if [[ "$TARGET" == "clean" ]]; then
  info "Cleaning build artifacts..."
  flutter clean
  rm -rf build/
  success "Clean complete"
  exit 0
fi

# ── Dependencies ───────────────────────────────────────────────────────────
info "Getting dependencies..."
flutter pub get

# ── Code generation ────────────────────────────────────────────────────────
info "Running code generation (freezed + riverpod)..."
dart run build_runner build --delete-conflicting-outputs
success "Code generation done"

# ── Analyze ────────────────────────────────────────────────────────────────
info "Analyzing code..."
flutter analyze --no-fatal-infos
success "Analysis passed"

# ── Android ────────────────────────────────────────────────────────────────
build_android() {
  info "Building Android APK (release, split per ABI)..."
  flutter build apk --release --split-per-abi
  success "APK saved to: build/app/outputs/flutter-apk/"
  ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true

  info "Building Android AAB (release)..."
  flutter build appbundle --release
  success "AAB saved to: build/app/outputs/bundle/release/"
  ls -lh build/app/outputs/bundle/release/*.aab 2>/dev/null || true
}

# ── Windows ────────────────────────────────────────────────────────────────
build_windows() {
  if [[ "$(uname -s)" != "MINGW"* ]] && [[ "$(uname -s)" != "CYGWIN"* ]] && [[ "${OS:-}" != "Windows_NT" ]]; then
    warn "Windows build requires Windows OS. Skipping on $(uname -s)."
    return
  fi
  info "Enabling Windows desktop target..."
  flutter config --enable-windows-desktop
  info "Building Windows EXE (release)..."
  flutter build windows --release
  success "EXE saved to: build/windows/x64/runner/Release/"
  ls -lh "build/windows/x64/runner/Release/"*.exe 2>/dev/null || true
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$TARGET" in
  android) build_android ;;
  windows) build_windows ;;
  all)     build_android; build_windows ;;
  *)       error "Unknown target: $TARGET. Use: android | windows | all | clean" ;;
esac

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Build Complete! 🎉${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
