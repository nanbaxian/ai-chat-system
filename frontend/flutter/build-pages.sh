#!/usr/bin/env bash
set -euo pipefail

# Download Flutter SDK if missing or outdated
FLUTTER_VERSION="3.38.5"
FLUTTER_ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

download_needed=0
if [ -d "flutter" ]; then
  if [ -f "flutter/version" ]; then
    current_version=$(cat flutter/version)
  else
    current_version=""
  fi

  if [ "$current_version" != "$FLUTTER_VERSION" ]; then
    rm -rf flutter
    download_needed=1
  fi
else
  download_needed=1
fi

if [ "$download_needed" -eq 1 ]; then
  curl -sSL "${FLUTTER_ARCHIVE_URL}" | tar -xJ
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter precache

flutter pub get
flutter build web  --dart-define=SIGNAL_ENDPOINT="https://voice-ai-demo.flashcodingcompany1.workers.dev/signal" --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"
