#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage:
  ./scripts/regenerate_splash.sh [image_path]

Description:
  Regenerates iOS launch images with flutter_native_splash,
  then overwrites Android manual splash resources with the same image.

Arguments:
  image_path   Optional. Source image path relative to the project root.
               Defaults to splash.png
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_IMAGE_REL="${1:-splash.png}"
SOURCE_IMAGE="${PROJECT_ROOT}/${SOURCE_IMAGE_REL}"

if [[ ! -f "${SOURCE_IMAGE}" ]]; then
  echo "Splash source image not found: ${SOURCE_IMAGE_REL}" >&2
  exit 1
fi

ANDROID_SPLASH_TARGETS=(
  "android/app/src/main/res/drawable-mdpi/splash.png"
  "android/app/src/main/res/drawable-hdpi/splash.png"
  "android/app/src/main/res/drawable-xhdpi/splash.png"
  "android/app/src/main/res/drawable-xxhdpi/splash.png"
  "android/app/src/main/res/drawable-xxxhdpi/splash.png"
)

cd "${PROJECT_ROOT}"

echo "Using splash source: ${SOURCE_IMAGE_REL}"
echo "Regenerating iOS splash assets with flutter_native_splash..."
dart run flutter_native_splash:create

echo "Syncing Android manual splash assets..."
for target in "${ANDROID_SPLASH_TARGETS[@]}"; do
  cp -f "${SOURCE_IMAGE}" "${PROJECT_ROOT}/${target}"
  echo "Updated ${target}"
done

echo "Splash regeneration complete."
