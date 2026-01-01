#!/usr/bin/env bash
set -euo pipefail

# Download Flutter SDK if missing
if [ ! -d "flutter" ]; then
  archive_url="$(
    python - <<'PY'
import json, sys, urllib.request

url = "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
data = json.load(urllib.request.urlopen(url))
stable_hash = data["current_release"]["stable"]
base_url = data["base_url"]

for release in data["releases"]:
    if release["hash"] == stable_hash:
        print(f"{base_url}/{release['archive']}")
        sys.exit(0)

sys.exit(1)
PY
  )"

  curl -sSL "${archive_url}" | tar -xJ
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter precache

flutter pub get
flutter build web  --dart-define=SIGNAL_ENDPOINT="https://voice-ai-demo.flashcodingcompany1.workers.dev/signal" --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"
