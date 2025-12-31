import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class FakeWaveform extends StatefulWidget {
  final bool active;
  const FakeWaveform({super.key, required this.active});

  @override
  State<FakeWaveform> createState() => _FakeWaveformState();
}

class _FakeWaveformState extends State<FakeWaveform> {
  final _rand = Random();
  Timer? _timer;
  List<double> bars = List.filled(12, 0.2);

  @override
  void didUpdateWidget(covariant FakeWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        setState(() {
          bars = bars
              .map((_) => 0.2 + _rand.nextDouble() * 0.8)
              .toList();
        });
      });
    } else if (!widget.active) {
      _timer?.cancel();
      _timer = null;
      setState(() {
        bars = List.filled(12, 0.2);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: bars
          .map((h) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 6,
                  height: 40 * h,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ))
          .toList(),
    );
  }
}
