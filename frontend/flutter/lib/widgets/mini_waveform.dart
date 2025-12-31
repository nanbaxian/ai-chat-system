import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class MiniWaveform extends StatefulWidget {
  final bool active;
  const MiniWaveform({super.key, required this.active});

  @override
  State<MiniWaveform> createState() => _MiniWaveformState();
}

class _MiniWaveformState extends State<MiniWaveform> {
  final _rand = Random();
  Timer? _timer;
  List<double> _bars = List.filled(8, 0.3);

  @override
  void didUpdateWidget(covariant MiniWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        setState(() {
          _bars = _bars.map((_) => 0.25 + _rand.nextDouble() * 0.75).toList();
        });
      });
    } else if (!widget.active) {
      _timer?.cancel();
      _timer = null;
      setState(() => _bars = List.filled(8, 0.3));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _bars.map((h) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 4,
            height: 14 * h,
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }).toList(),
    );
  }
}
