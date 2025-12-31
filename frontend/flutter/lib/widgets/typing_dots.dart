import 'dart:async';
import 'package:flutter/material.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 350), (_) {
      setState(() => _i = (_i + 1) % 3);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (_i + 1);
    return Text('Thinking$dots', style: Theme.of(context).textTheme.bodySmall);
  }
}
