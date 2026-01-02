import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

typedef AudioChunkCallback = void Function(List<int> chunk);

class AudioCapture {
  AudioCapture(this.onChunk, {int targetSampleRate = 16000}) : targetSampleRate = targetSampleRate;

  final AudioChunkCallback onChunk;
  final int targetSampleRate;

  dynamic _context;
  dynamic _processor;
  dynamic _source;
  dynamic _silenceNode;

  int _chunkCount = 0;
  int _sampleSum = 0;
  DateTime _windowStart = DateTime.now();

  void start(Object? stream) {
    print('[AudioCapture] start called stream=$stream');
    if (stream is html.MediaStream) {
      _ensureContext();
      _connectStream(stream);
    }
  }

  void stop() {
    if (_processor != null) {
      js_util.callMethod(_processor, 'disconnect', []);
      js_util.callMethod(_processor, 'removeEventListener', ['audioprocess', _onAudioProcess]);
    }
    if (_source != null) {
      js_util.callMethod(_source, 'disconnect', []);
      _source = null;
    }
    if (_silenceNode != null) {
      js_util.callMethod(_silenceNode, 'disconnect', []);
      _silenceNode = null;
    }
    if (_context != null) {
      js_util.callMethod(_context, 'close', []);
      _context = null;
    }
    _processor = null;
    print('[AudioCapture] stopped');
  }

  void _ensureContext() {
    if (_context != null) return;
    final constructor = js_util.getProperty(html.window, 'AudioContext') ??
        js_util.getProperty(html.window, 'webkitAudioContext');
    if (constructor == null) {
      print('[AudioCapture] AudioContext constructor missing');
      return;
    }
    final options = js_util.jsify({'sampleRate': targetSampleRate.toDouble()});
    _context = js_util.callConstructor(constructor, [options]);
    print('[AudioCapture] created AudioContext sampleRate=${targetSampleRate}');
  }

  void _connectStream(html.MediaStream stream) {
    if (_context == null) return;

    _processor = js_util.callMethod(_context, 'createScriptProcessor', [4096, 1, 1]);
    js_util.callMethod(_processor, 'addEventListener', [
      'audioprocess',
      js_util.allowInterop((event) => _onAudioProcess(event)),
    ]);

    _silenceNode = js_util.callMethod(_context, 'createGain', []);
    final gain = js_util.getProperty(_silenceNode, 'gain');
    js_util.setProperty(gain, 'value', 0);
    final destination = js_util.getProperty(_context, 'destination');
    js_util.callMethod(_silenceNode, 'connect', [destination]);

    _source = js_util.callMethod(_context, 'createMediaStreamSource', [stream]);
    js_util.callMethod(_source, 'connect', [_processor]);
    js_util.callMethod(_processor, 'connect', [_silenceNode]);
    print('[AudioCapture] connected stream, processor bufferSize=4096');
  }

  void _onAudioProcess(dynamic event) {
    final buffer = js_util.callMethod(js_util.getProperty(event, 'inputBuffer'), 'getChannelData', [0]) as Float32List?;
    if (buffer == null) return;

    final chunk = _convertToInt16(buffer);
    if (chunk.isNotEmpty) {
      final firstSamples = chunk.take(5).toList();
      print('[AudioCapture] chunk length=${chunk.length} firstSamples=$firstSamples');
      _chunkCount++;
      _sampleSum += chunk.length;
      final now = DateTime.now();
      if (now.difference(_windowStart) > const Duration(seconds: 1)) {
        print('[AudioCapture] per-second chunks=$_chunkCount samples=$_sampleSum');
        _chunkCount = 0;
        _sampleSum = 0;
        _windowStart = now;
      }
    } else {
      print('[AudioCapture] chunk empty');
    }
    if (chunk.isNotEmpty) {
      onChunk(chunk);
    }
  }

  List<int> _convertToInt16(Float32List data) {
    final result = Int16List(data.length);
    for (var i = 0; i < data.length; i++) {
      final sample = data[i].clamp(-1.0, 1.0);
      result[i] = (sample * 0x7fff).toInt();
    }
    return result;
  }
}
