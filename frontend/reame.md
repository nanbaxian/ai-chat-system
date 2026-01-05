local build:
flutter build web  --dart-define=SIGNAL_ENDPOINT=https://aichatback.standirect.ca/signal --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"


cloudflare build:
curl -sSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.10.5-stable.tar.xz | tar -xJ
export PATH="$PWD/flutter/bin:$PATH"
flutter config --no-analytics
flutter pub get
flutter build web  --dart-define=SIGNAL_ENDPOINT=https://aichatback.standirect.ca/signal --dart-define=SIGNAL_AUTHORIZATION="Bearer demo-token"

输出目录指定为 frontend/flutter/build/web