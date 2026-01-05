#!/usr/bin/env bash
set -euo pipefail

export PATH="$PATH:/opt/flutter/bin"
cd "$(dirname "$0")"

flutter pub get
flutter build web --release

mkdir -p build/web/scripts
cp ../scripts/inject_native_stream.js build/web/scripts/

python - <<'PY'
from pathlib import Path
path = Path("build/web/index.html")
text = path.read_text(encoding="utf-8")
marker = '<script src="scripts/inject_native_stream.js"></script>'
if marker not in text:
    insert = "\n  " + marker + "\n"
    if "</body>" in text:
        text = text.replace("</body>", insert + "</body>", 1)
    else:
        text += insert
    path.write_text(text, encoding="utf-8")
PY
