import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'widgets/chat_bubble.dart';
import 'widgets/typing_dots.dart';
import 'widgets/voice_bar.dart';
import 'src/audio_capture.dart';

const _signalEndpoint = String.fromEnvironment(
  'SIGNAL_ENDPOINT',
  defaultValue: 'http://127.0.0.1:3001/signal',
);
const _authorizationHeader = String.fromEnvironment(
  'SIGNAL_AUTHORIZATION',
  defaultValue: 'Bearer demo-token',
);
const _targetSampleRate = 16000;

void main() => runApp(const App());

class ChatMessage {
  final ChatRole role;
  String text;
  bool streaming;
  ChatMessage({required this.role, required this.text, this.streaming = false});
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      fontFamily: 'NotoSans',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10A37F)),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: base.colorScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: base.colorScheme.surface,
          foregroundColor: base.colorScheme.onSurface,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  late final AudioCapture _audioCapture;
  final String _sessionId = _makeSessionId();
  bool _sessionReady = false;

  final List<ChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();

  VoiceUiState _state = VoiceUiState.idle;
  bool _micOn = true;
  int _chunkMeter = 0;
  DateTime _chunkMeterStart = DateTime.now();

  // provider + metrics
  String _ttsProvider = 'Auto';
  int? _ttfaMs; // latest ttfa
  int? _ttfaDisplay; // animated ticker
  Timer? _ttfaTicker;

  // “speaking” pulse – set true when tts.audio arrives, auto reset after 650ms
  bool _aiSpeaking = false;
  Timer? _speakingTimer;

  // For user partial draft
  String _userDraft = '';

  @override
  void initState() {
    super.initState();
    _audioCapture = AudioCapture(_handleAudioChunk, targetSampleRate: _targetSampleRate);
    initRTC();
  }

  @override
  void dispose() {
    _audioCapture.stop();
    _speakingTimer?.cancel();
    _ttfaTicker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> initRTC() async {
    pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    debugPrint('[initRTC] peer connection ready');

    pc!.onIceCandidate = (candidate) {
      if (candidate != null) {
        unawaited(_sendIceCandidate(candidate));
      }
    };

    dc = await pc!.createDataChannel('events', RTCDataChannelInit());
    dc!.onMessage = _onEvent;

    final stream = await navigator.mediaDevices.getUserMedia({'audio': true});
    debugPrint('[initRTC] got user media stream tracks=${stream.getTracks().length}');
    for (final t in stream.getTracks()) {
      pc!.addTrack(t, stream);
    }

    _audioCapture.start(stream);
    debugPrint('[initRTC] audio capture started');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  ChatMessage? _lastAssistant() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == ChatRole.assistant) return _messages[i];
    }
    return null;
  }

  void _ensureAssistantStreaming() {
    final last = _lastAssistant();
    if (last != null && last.streaming) return;
    _messages.add(ChatMessage(role: ChatRole.assistant, text: '', streaming: true));
  }

  void _commitUserFinal(String text) {
    _userDraft = '';
    _messages.add(ChatMessage(role: ChatRole.user, text: text, streaming: false));
  }

  void _appendAssistantDelta(String delta) {
    _ensureAssistantStreaming();
    final last = _lastAssistant()!;
    last.text += delta;
  }

  void _finishAssistantStreaming() {
    final last = _lastAssistant();
    if (last != null) last.streaming = false;
  }

  void _animateTTFA(int target) {
    _ttfaMs = target;
    _ttfaTicker?.cancel();

    final start = _ttfaDisplay ?? target;
    final diff = target - start;
    if (diff == 0) {
      setState(() => _ttfaDisplay = target);
      return;
    }

    const steps = 10;
    int i = 0;
    _ttfaTicker = Timer.periodic(const Duration(milliseconds: 40), (t) {
      i++;
      final v = start + (diff * i / steps).round();
      if (!mounted) return;
      setState(() => _ttfaDisplay = v);
      if (i >= steps) t.cancel();
    });
  }

  void _markSpeakingPulse() {
    _aiSpeaking = true;
    _speakingTimer?.cancel();
    _speakingTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _aiSpeaking = false);
      if (_state == VoiceUiState.speaking) {
        setState(() => _state = VoiceUiState.idle);
      }
    });
  }

  void _onEvent(RTCDataChannelMessage msg) {
    final evt = jsonDecode(msg.text);
    final type = evt['type'];

    setState(() {
      switch (type) {
        case 'tts.provider':
          _ttsProvider = (evt['name'] ?? 'Auto').toString();
          break;

        case 'metrics.ttfa':
          final ms = evt['ms'];
          if (ms is num) _animateTTFA(ms.round());
          break;

        case 'stt.partial':
          _userDraft = (evt['text'] ?? '').toString();
          _state = VoiceUiState.listening;
          break;

        case 'stt.final':
          final t = (evt['text'] ?? '').toString();
          if (t.trim().isNotEmpty) _commitUserFinal(t);
          _ensureAssistantStreaming();
          _state = VoiceUiState.thinking;
          // reset TTFA display for this turn
          _ttfaMs = null;
          _ttfaDisplay = null;
          break;

        case 'llm.delta':
          _appendAssistantDelta((evt['text'] ?? '').toString());
          break;

        case 'llm.final':
          _finishAssistantStreaming();
          if (!_aiSpeaking) _state = VoiceUiState.idle;
          break;

        case 'tts.audio':
          _markSpeakingPulse();
          _state = VoiceUiState.speaking;
          break;

        default:
          break;
      }
    });

    _scrollToBottom();
  }

  void _sendCancel() {
    if (dc?.state != RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[_sendCancel] data channel not open (${dc?.state}), skipping cancel');
      return;
    }
    try {
      debugPrint('[_sendCancel] clearing active request');
      dc?.send(RTCDataChannelMessage(jsonEncode({'type': 'cancel'})));
    } catch (e, st) {
      debugPrint('[ _startSignaling] error: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _startSignaling() async {
    debugPrint('[_startSignaling] triggered, pc=${pc != null}, sessionId=$_sessionId');
    if (pc == null) return;
    try {
      final offer = await pc!.createOffer({'offerToReceiveAudio': false});
      debugPrint('[_startSignaling] offer created (${offer.type})');
      await pc!.setLocalDescription(offer);
      debugPrint('[_startSignaling] local description set');
      final answer = await _sendOffer(offer);
      final remoteDesc = RTCSessionDescription(
        answer['sdp'] as String,
        answer['type'] as String,
      );
      await pc!.setRemoteDescription(remoteDesc);
      debugPrint('[_startSignaling] remote description set, answer type ${remoteDesc.type}');
      setState(() => _sessionReady = true);
    } catch (e, st) {
      debugPrint('Signal exchange failed: $e\n$st');
    }
  }

  Future<Map<String, dynamic>> _sendOffer(RTCSessionDescription offer) async {
    try {
      final response = await http.post(
      Uri.parse(_signalEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authorizationHeader,
      },
      body: jsonEncode({
        'sessionId': _sessionId,
        'type': 'offer',
        'payload': offer.toMap(),
      }),
    );
      if (response.statusCode >= 400) {
        throw Exception('Offer failed (${response.statusCode}): ${response.body}');
      }
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('[_sendOffer] answer received: ${result['type']}');
      return result;
    } catch (e, st) {
      debugPrint('[_sendOffer] error posting offer: $e\n$st');
      rethrow;
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    debugPrint('[_sendIceCandidate] candidate ${candidate.candidate}');
    try {
      final response = await http.post(
      Uri.parse(_signalEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authorizationHeader,
      },
      body: jsonEncode({
        'sessionId': _sessionId,
        'type': 'ice',
        'payload': candidate.toMap(),
      }),
    );
      if (response.statusCode >= 400) {
        debugPrint('ICE publish failed (${response.statusCode}): ${response.body}');
      } else {
        debugPrint('[_sendIceCandidate] accepted (${response.statusCode})');
      }
    } catch (e, st) {
      debugPrint('[_sendIceCandidate] error: $e\n$st');
    }
  }

  void _handleAudioChunk(List<int> chunk) {
    debugPrint('[_handleAudioChunk] entry chunk=${chunk.length}');
    final reason = <String>[];
    if (!_sessionReady) reason.add('!sessionReady');
    if (_state != VoiceUiState.listening) reason.add('state=$_state');
    if (chunk.isEmpty) reason.add('chunk empty');
    if (dc?.state != RTCDataChannelState.RTCDataChannelOpen) reason.add('dc=${dc?.state}');
    if (reason.isNotEmpty) {
      debugPrint('[_handleAudioChunk] skipped (${reason.join(', ')}); chunk=${chunk.length} micOn=$_micOn');
      return;
    }
    debugPrint('[_handleAudioChunk] allowed chunk=${chunk.length} micOn=$_micOn dc=${dc?.state}');
    _chunkMeter += chunk.length;
    final now = DateTime.now();
    if (now.difference(_chunkMeterStart) >= const Duration(seconds: 1)) {
      debugPrint('[_handleAudioChunk] meter: ${_chunkMeter} samples/sec');
      _chunkMeter = 0;
      _chunkMeterStart = now;
    }
    _sendAudioChunk(chunk);
  }

  void _sendAudioChunk(List<int> chunk) {
    debugPrint('[_sendAudioChunk] sending ${chunk.length} bytes');
    final payload = jsonEncode({'type': 'audio_in', 'data': chunk});
    try {
      dc?.send(RTCDataChannelMessage(payload));
    } catch (e) {
      debugPrint('Failed to send audio chunk: $e');
    }
  }

  void _logDataChannelState(String prefix) {
    debugPrint('[$prefix] DataChannel state=${dc?.state} bufferedAmount=${dc?.bufferedAmount}');
  }

  static String _makeSessionId() {
    final rnd = Random();
    return 'web-${DateTime.now().millisecondsSinceEpoch}-${rnd.nextInt(1 << 31).toRadixString(16)}';
  }

  void _onMicTap() {
    // ChatGPT-like: when user starts, barge-in immediately
    if (_sessionReady && _state != VoiceUiState.idle) {
      _sendCancel();
    } else {
      debugPrint('[_onMicTap] no active turn to cancel (sessionReady=$_sessionReady state=$_state)');
    }
    debugPrint('[_onMicTap] trigger mic, state=$_state');
    setState(() {
      _micOn = true;
      _state = VoiceUiState.listening;
    });
    _logDataChannelState('_onMicTap');
  }

  void _onInterrupt() {
        _sendCancel();
        setState(() {
          _aiSpeaking = false;
          _state = VoiceUiState.idle;
        });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final listItems = <Widget>[];
    for (final m in _messages) {
      final isAssistant = m.role == ChatRole.assistant;
      final typing = isAssistant && m.streaming && m.text.trim().isEmpty && _state == VoiceUiState.thinking;

      Widget? footer;
      if (isAssistant) {
        if (_aiSpeaking) {
          final ttfa = _ttfaDisplay == null ? '' : ' · TTFA ${_ttfaDisplay}ms';
          footer = Text('Speaking · ${_ttsProvider.toUpperCase()}$ttfa');
        } else if (typing) {
          footer = const TypingDots();
        } else if (_state == VoiceUiState.thinking && m.streaming) {
          footer = const TypingDots();
        }
      }

      listItems.add(ChatBubble(
        role: m.role,
        text: m.text,
        streaming: m.streaming,
        speaking: isAssistant && _aiSpeaking,
        footer: footer,
      ));
    }

    if (_userDraft.trim().isNotEmpty) {
      listItems.add(ChatBubble(
        role: ChatRole.user,
        text: _userDraft,
        streaming: true,
        speaking: false,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Chat'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _state == VoiceUiState.speaking ? cs.primary : cs.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    'TTS: ${_ttsProvider.toUpperCase()}${_ttfaDisplay == null ? '' : ' · TTFA ${_ttfaDisplay}ms'}',
                    key: ValueKey('${_ttsProvider}_${_ttfaDisplay ?? ''}'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _sessionReady ? null : _startSignaling,
                    child: Text(_sessionReady ? 'Signaling ready' : 'Start signaling'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 6, bottom: 18),
              children: [
                const SizedBox(height: 8),
                ...listItems,
                const SizedBox(height: 30),
              ],
            ),
          ),
          VoiceBar(
            state: _state,
            micOn: _micOn,
            onMic: _onMicTap,
            onInterrupt: _onInterrupt,
          ),
        ],
      ),
    );
  }
}
