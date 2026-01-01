#!/usr/bin/env bash
set -euo pipefail

# Download Flutter SDK if missing or outdated
IFS=$'\n' read -r stable_version archive_url <<'PY'
import json, sys, urllib.request

url = "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
data = json.load(urllib.request.urlopen(url))
stable_hash = data["current_release"]["stable"]
base_url = data["base_url"]

for release in data["releases"]:
    if release["hash"] == stable_hash:
        print(release["version"])
        print(f"{base_url}/{release['archive']}")
        sys.exit(0)

sys.exit(1)
PY
IFS=$' \t\n' # reset IFS

download_needed=0
if [ -d "flutter" ]; then
  if [ -f "flutter/version" ]; then
    current_version=$(cat flutter/version)
  else
    current_version=""
  fi

  if [ "$current_version" != "$stable_version" ]; then
    rm -rf flutter
    download_needed=1
  fi
else
  download_needed=1
fi

if [ "$download_needed" -eq 1 ]; then
  curl -sSL "${archive_url}" | tar -xJ
fi

export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter precache

flutter pub get
flutter build web  --dart-define=SIGNAL_ENDPOINT="https://voice-ai-demo.flashcodingcompany1.workers.dev/signal" --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"
