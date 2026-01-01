#!/usr/bin/env bash
set -euo pipefail

# Download Flutter SDK if missing
if [ ! -d "flutter" ]; then
  curl -sSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_latest-stable.tar.xz | tar -xJ
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter precache

flutter pub get
flutter build web  --dart-define=SIGNAL_ENDPOINT="https://voice-ai-demo.flashcodingcompany1.workers.dev/signal" --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"
