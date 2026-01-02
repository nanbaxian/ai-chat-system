import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;

typedef VoidCallbackJs = void Function(dynamic);

void main() {
  runApp(const TestFrontApp());
}

class TestFrontApp extends StatelessWidget {
  const TestFrontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test Front STT',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10A37F)),
        useMaterial3: true,
      ),
      home: const SpeechPage(),
    );
  }
}

class SpeechPage extends StatefulWidget {
  const SpeechPage({super.key});

  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  dynamic _recognition;
  bool _supported = true;
  bool _listening = false;
  String _status = '等待开启麦克风';
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    _initRecognition();
  }

  void _initRecognition() {
    final factory = js_util.getProperty(html.window, 'SpeechRecognition') ??
        js_util.getProperty(html.window, 'webkitSpeechRecognition');
    if (factory == null) {
      setState(() {
        _supported = false;
        _status = '浏览器不支持 Web Speech API，请使用 Chrome';
      });
      return;
    }

    final recognition = js_util.callConstructor(factory, []);
    js_util.setProperty(recognition, 'continuous', true);
    js_util.setProperty(recognition, 'interimResults', true);
    js_util.setProperty(recognition, 'lang', 'zh-CN');

    js_util.setProperty(
      recognition,
      'onstart',
      allowInterop((dynamic _) {
        setState(() {
          _listening = true;
          _status = '正在听写...';
        });
      }),
    );

    js_util.setProperty(
      recognition,
      'onend',
      allowInterop((dynamic _) {
        setState(() {
          _listening = false;
          _status = '识别已停止，点击开始';
        });
      }),
    );

    js_util.setProperty(
      recognition,
      'onerror',
      allowInterop((dynamic event) {
        final error = js_util.getProperty(event, 'error');
        setState(() {
          _status = '识别错误：$error';
        });
        debugPrint('SpeechRecognition error: $error');
      }),
    );

    js_util.setProperty(
      recognition,
      'onresult',
      allowInterop((dynamic event) {
        final results = js_util.getProperty(event, 'results');
        final resultIndex = js_util.getProperty(event, 'resultIndex') as int? ?? 0;
        final resultsLength = js_util.getProperty(results, 'length') as int? ?? 0;
        String interim = '';
        for (var i = resultIndex; i < resultsLength; i++) {
          final result = js_util.getProperty(results, i);
          final transcript =
              js_util.getProperty(js_util.getProperty(result, 0), 'transcript') as String;
          final isFinal = js_util.getProperty(result, 'isFinal') as bool;
          if (isFinal) {
            _transcript += transcript + '\n';
          } else {
            interim += transcript;
          }
        }
        setState(() {
          _transcript = _transcript + (interim.isNotEmpty ? interim : '');
        });
      }),
    );

    _recognition = recognition;
  }

  void _toggleListening() {
    if (!_supported || _recognition == null) return;
    if (_listening) {
      js_util.callMethod(_recognition, 'stop', []);
    } else {
      setState(() {
        _transcript = '';
      });
      js_util.callMethod(_recognition, 'start', []);
    }
  }

  @override
  void dispose() {
    if (_recognition != null) {
      js_util.callMethod(_recognition, 'stop', []);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Front STT'),
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic, size: 64, color: Colors.green),
                const SizedBox(height: 12),
                Text(
                  _supported ? '按下开始识别' : '浏览器不支持 Web Speech API',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(_status, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _supported ? _toggleListening : null,
                  child: Text(_listening ? '停止识别' : '开始识别'),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _transcript.isEmpty ? '识别内容会显示在这里' : _transcript,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
