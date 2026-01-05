import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'widgets/chat_bubble.dart';
import 'widgets/typing_dots.dart';
import 'widgets/voice_bar.dart';
import 'src/audio_capture.dart';

const _signalEndpoint = String.fromEnvironment(
  'SIGNAL_ENDPOINT',
  defaultValue: 'https://aichatback.standirect.ca/signal',
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
  late final dynamic _audioContext;
  dynamic _localStream;
  dynamic _localNativeStream;
  bool _audioCaptureStarted = false;
  final List<Object> _activeAudioSources = [];
  num? _nextAudioStartTime;

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
    _audioContext = _createAudioContext();
    initRTC();
  }

  dynamic _createAudioContext() {
    final constructor =
        js_util.getProperty(html.window, 'AudioContext') ?? js_util.getProperty(html.window, 'webkitAudioContext');
    if (constructor == null) return null;
    try {
      return js_util.callConstructor(constructor, []);
    } catch (error) {
      debugPrint('[_createAudioContext] failed to construct AudioContext: $error');
      return null;
    }
  }

  @override
  void dispose() {
    _audioCapture.stop();
    _speakingTimer?.cancel();
    _ttfaTicker?.cancel();
    _scroll.dispose();
    if (_audioContext != null) {
      try {
        js_util.callMethod(_audioContext, 'close', []);
      } catch (_) {}
    }
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

    try {
      debugPrint('[initRTC] requesting user media');
      final stream = await navigator.mediaDevices.getUserMedia({'audio': true});
      debugPrint('[initRTC] user media granted tracks=${stream.getTracks().length}');
      debugPrint('[initRTC] got user media stream tracks=${stream.getTracks().length} active=${stream.active} id=${stream.id}');
      _logStreamTracks('initRTC', stream);
      for (final track in stream.getTracks()) {
        js_util.callMethod(track, 'addEventListener', [
          'ended',
          js_util.allowInterop((event) {
            final trackId = js_util.getProperty(track, 'id') ?? 'unknown';
            debugPrint('[_track] initRTC track ended id=$trackId kind=${js_util.getProperty(track, 'kind') ?? 'unknown'}');
          })
        ]);
        pc!.addTrack(track, stream);
      }

      _localStream = stream;
      _localNativeStream = _resolveNativeStream(stream);
      debugPrint('[initRTC] local stream stored active=${stream.active} id=${stream.id}');
    } catch (error, st) {
      debugPrint('[initRTC] getUserMedia failed: $error');
      debugPrint(st.toString());
      rethrow;
    }
  }

  void _ensureAudioCapture() {
    if (_audioCaptureStarted) {
      debugPrint('[_ensureAudioCapture] capture already started (streamId=${_localStream?.id ?? 'null'})');
      return;
    }
    final stream = _localStream;
    if (stream == null) {
      debugPrint('[_ensureAudioCapture] local stream not ready yet, cannot start capture');
      return;
    }
    _localNativeStream = _extractNativeStream(stream);
    if (_localNativeStream == null) {
      debugPrint('[_ensureAudioCapture] native stream missing, waiting for native tracks');
      return;
    }
    _logStreamTracks('ensureAudioCapture', stream);
    final streamId = js_util.getProperty(stream, 'id') ?? js_util.getProperty(_localNativeStream, 'id');
    final active = js_util.getProperty(stream, 'active') ?? js_util.getProperty(_localNativeStream, 'active');
    debugPrint('[_ensureAudioCapture] starting capture streamId=${streamId ?? 'unknown'} active=${active ?? 'unknown'}');
    _audioCapture.start(_localNativeStream);
    _audioCaptureStarted = true;
    debugPrint('[audio] capture started');
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

  void _logStreamTracks(String prefix, dynamic stream) {
    final nativeStream = _resolveNativeStream(stream);
    final streamId = js_util.getProperty(stream, 'id') ?? (nativeStream != null ? js_util.getProperty(nativeStream, 'id') : null);
    final active = js_util.getProperty(stream, 'active') ?? (nativeStream != null ? js_util.getProperty(nativeStream, 'active') : null);
    if (nativeStream == null) {
      debugPrint('[$prefix] stream id=${streamId ?? 'unknown'} native stream missing trackCount=0 active=${active ?? 'unknown'}');
      return;
    }
    final tracks = List<dynamic>.from(js_util.callMethod(nativeStream, 'getAudioTracks', []));
    debugPrint('[$prefix] stream id=${streamId ?? 'unknown'} trackCount=${tracks.length} active=${active ?? 'unknown'}');
    for (final track in tracks) {
      final trackId = js_util.getProperty(track, 'id');
      final kind = js_util.getProperty(track, 'kind');
      final enabled = js_util.getProperty(track, 'enabled');
      final muted = js_util.getProperty(track, 'muted');
      final readyState = js_util.getProperty(track, 'readyState');
      debugPrint(
        '[$prefix] track id=${trackId ?? 'unknown'} kind=${kind ?? 'unknown'} enabled=${enabled ?? 'unknown'} muted=${muted ?? 'unknown'} readyState=${readyState ?? 'unknown'}',
      );
      final addEventListener = js_util.getProperty(track, 'addEventListener');
      if (addEventListener != null) {
        js_util.callMethod(track, 'addEventListener', [
          'ended',
          js_util.allowInterop((event) {
            debugPrint('[$prefix] track ended id=${trackId ?? 'unknown'} readyState=${readyState ?? 'unknown'}');
          })
        ]);
      } else {
        debugPrint('[$prefix] track has no addEventListener, skipping');
      }
    }
  }

  dynamic _resolveNativeStream(dynamic stream) {
    if (stream == null) return null;
    if (stream is html.MediaStream) return stream;
    final jsStream = js_util.getProperty(stream, 'jsStream');
    if (jsStream != null) return jsStream;
    final mediaStream = js_util.getProperty(stream, 'mediaStream');
    if (mediaStream != null) return mediaStream;
    final getTracks = js_util.getProperty(stream, 'getTracks');
    if (getTracks != null) return stream;
    return null;
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

  void _playTtsAudioChunk(String base64Data, num sampleRate) {
    if (base64Data.isEmpty) return;
    if (_audioContext == null) return;
    debugPrint('[_playTtsAudioChunk] chunkLen=${base64Data.length} sampleRate=$sampleRate');
    final decoded = base64Decode(base64Data);
    debugPrint('[_playTtsAudioChunk] decodedBytes=${decoded.length}');
    _resumeAudioContext();

    var played = false;

    void fallback(_) {
      if (played) return;
      played = true;
      _playPcmChunk(decoded, sampleRate);
    }

    void handleBuffer(Object audioBuffer) {
      if (played) return;
      played = true;
      _scheduleAudioBuffer(audioBuffer);
    }

    final arrayBuffer = _sliceArrayBuffer(decoded);
    if (arrayBuffer == null) {
      fallback(null);
      return;
    }

    try {
      final promise = js_util.callMethod(
        _audioContext,
        'decodeAudioData',
        [arrayBuffer, js_util.allowInterop(handleBuffer), js_util.allowInterop(fallback)],
      );
      if (promise != null) {
        js_util.promiseToFuture(promise).then((audioBuffer) {
          handleBuffer(audioBuffer as Object);
        }).catchError(fallback);
      }
    } catch (_) {
      fallback(null);
    }
  }

  void _resumeAudioContext() {
    if (_audioContext == null) return;
    try {
      js_util.callMethod(_audioContext, 'resume', []);
    } catch (_) {}
  }

  void _stopCurrentAudio() {
    if (_activeAudioSources.isEmpty) return;
    for (final source in List.of(_activeAudioSources)) {
      _activeAudioSources.remove(source);
      try {
        js_util.callMethod(source, 'stop', []);
      } catch (_) {}
      try {
        js_util.callMethod(source, 'disconnect', []);
      } catch (_) {}
    }
    _nextAudioStartTime = null;
  }

  void _scheduleAudioBuffer(Object audioBuffer) {
    if (_audioContext == null) return;
    final source = js_util.callMethod(_audioContext, 'createBufferSource', []);
    js_util.setProperty(source, 'buffer', audioBuffer);
    js_util.callMethod(source, 'connect', [js_util.getProperty(_audioContext, 'destination')]);
    final rawCurrentTime = js_util.getProperty(_audioContext, 'currentTime');
    final currentTime = rawCurrentTime is num ? rawCurrentTime : 0;
    final startTime = (_nextAudioStartTime != null && _nextAudioStartTime! > currentTime ? _nextAudioStartTime! : currentTime);
    js_util.callMethod(source, 'start', [startTime]);
    final duration = js_util.getProperty(audioBuffer, 'duration');
    _nextAudioStartTime = duration is num ? startTime + duration : startTime;
    _activeAudioSources.add(source);
    js_util.callMethod(source, 'addEventListener', [
      'ended',
      js_util.allowInterop((_) {
        try {
          js_util.callMethod(source, 'disconnect', []);
        } catch (_) {}
        _activeAudioSources.remove(source);
      })
    ]);
  }

  void _playPcmChunk(Uint8List decoded, num sampleRate) {
    if (_audioContext == null) return;
    final frameCount = decoded.length ~/ 2;
    if (frameCount <= 0) return;
    final audioBuffer = js_util.callMethod(
      _audioContext,
      'createBuffer',
      [1, frameCount, sampleRate.toDouble()],
    );
    final channelData = js_util.callMethod(audioBuffer, 'getChannelData', [0]) as Float32List;
    final bytes = ByteData.sublistView(decoded);
    for (var i = 0; i < frameCount; i++) {
      channelData[i] = (bytes.getInt16(i * 2, Endian.little) / 0x7fff).clamp(-1.0, 1.0);
    }
    _scheduleAudioBuffer(audioBuffer);
  }

  Object? _sliceArrayBuffer(Uint8List bytes) {
    final buffer = js_util.getProperty(bytes, 'buffer');
    final byteOffset = js_util.getProperty(bytes, 'byteOffset');
    final length = js_util.getProperty(bytes, 'length');
    if (buffer == null) return buffer;
    try {
      final offset = byteOffset is num ? byteOffset.toInt() : 0;
      final sliceLength = length is num ? length.toInt() : bytes.length;
      return js_util.callMethod(buffer, 'slice', [offset, offset + sliceLength]);
    } catch (_) {
      return buffer;
    }
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
          final data = (evt['data'] ?? '').toString();
          final rate = evt['sampleRate'] is num ? (evt['sampleRate'] as num).toDouble() : 24000.0;
          _playTtsAudioChunk(data, rate);
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
    final localStream = _localStream;
    final localActive = localStream != null ? js_util.getProperty(localStream, 'active') : null;
    debugPrint('[_onMicTap] local stream present=${localStream != null} active=${localActive ?? 'unknown'}');
    if (_localStream != null) {
      _logStreamTracks('_onMicTap', _localStream!);
    }
    _ensureAudioCapture();
    _audioCapture.resume();
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
