Flutter WebRTC MVP client (mic, datachannel, playback, cancel).

flutter pub get
flutter build web --release


server:
su - flutter
export PATH="$PATH:/opt/flutter/bin"
cd /www/wwwroot/default/ai-chat-system/frontend/flutter
./build_with_native_stream.sh
