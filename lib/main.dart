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

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    debugPrint('[_initWebRTC] requesting media permissions');
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    debugPrint('[_initWebRTC] media stream ready (${localStream?.id})');

    debugPrint('[_initWebRTC] creating peer connection');
    pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });
    debugPrint('[ _initWebRTC] peer connection created');

    localStream!.getTracks().forEach((track) {
      debugPrint('[ _initWebRTC] adding track ${track.kind}');
      pc!.addTrack(track, localStream!);
    });

    debugPrint('[_initWebRTC] creating data channel');
    dataChannel = await pc!.createDataChannel(
      'events',
      RTCDataChannelInit()..ordered = true,
    );
    debugPrint('[_initWebRTC] data channel created, readyState=${dataChannel?.state}');

    dataChannel!.onMessage = _onDataMessage;
  }

  void _onDataMessage(RTCDataChannelMessage msg) {
    debugPrint('[ _onDataMessage] raw message length=${msg.text.length}');
    final event = jsonDecode(msg.text);
    debugPrint('[ _onDataMessage] parsed ${event['type']}');
    if (event['type'] == 'tts.audio') {
      final bytes = base64Decode(event['data']);
      debugPrint('[ _onDataMessage] received audio chunk ${bytes.length} bytes');
      _playAudio(bytes);
    }
  }

  Future<void> _playAudio(Uint8List pcm16) async {
    debugPrint('[ _playAudio] received ${pcm16.length} bytes (stubbed playback)');
    // For MVP: this is where you connect PCM16 to AudioTrack / AudioSink
    // flutter_webrtc supports direct audio track playback
  }

  void _sendCancel() {
    debugPrint('[ _sendCancel] attempting to cancel via data channel ${dataChannel?.state}');
    try {
      dataChannel?.send(RTCDataChannelMessage(
        jsonEncode({'type': 'cancel'}),
      ));
      debugPrint('[ _sendCancel] cancel sent');
    } catch (err, st) {
      debugPrint('[ _sendCancel] failed to send cancel: $err');
      debugPrint(st.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ build] rebuilding UI');
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
