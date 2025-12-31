import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  runApp(const VoiceApp());
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: VoiceHome());
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key});

  @override
  State<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  RTCPeerConnection? pc;
  RTCDataChannel? dataChannel;
  MediaStream? localStream;
  final _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    localStream!.getTracks().forEach((track) {
      pc!.addTrack(track, localStream!);
    });

    dataChannel = await pc!.createDataChannel(
      'events',
      RTCDataChannelInit()..ordered = true,
    );

    dataChannel!.onMessage = _onDataMessage;
  }

  void _onDataMessage(RTCDataChannelMessage msg) {
    final event = jsonDecode(msg.text);
    if (event['type'] == 'tts.audio') {
      final bytes = base64Decode(event['data']);
      _playAudio(bytes);
    }
  }

  Future<void> _playAudio(Uint8List pcm16) async {
    // For MVP: this is where you connect PCM16 to AudioTrack / AudioSink
    // flutter_webrtc supports direct audio track playback
  }

  void _sendCancel() {
    dataChannel?.send(RTCDataChannelMessage(
      jsonEncode({'type': 'cancel'}),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice AI MVP')),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _sendCancel,
            child: const Text('Interrupt / Cancel'),
          )
        ],
      ),
    );
  }
}
