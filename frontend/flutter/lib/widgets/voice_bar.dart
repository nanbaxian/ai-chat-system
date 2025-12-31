import 'package:flutter/material.dart';

enum VoiceUiState { idle, listening, thinking, speaking }

class VoiceBar extends StatelessWidget {
  final VoiceUiState state;
  final VoidCallback onMic;
  final VoidCallback onInterrupt;
  final bool micOn;

  const VoiceBar({
    super.key,
    required this.state,
    required this.onMic,
    required this.onInterrupt,
    required this.micOn,
  });

  String get label {
    switch (state) {
      case VoiceUiState.listening: return 'Listening';
      case VoiceUiState.thinking: return 'Thinking';
      case VoiceUiState.speaking: return 'Speaking';
      case VoiceUiState.idle: default: return 'Ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                ),
                const Spacer(),
                Text('Barge-in', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: onInterrupt,
                  icon: const Icon(Icons.stop_circle_outlined),
                  tooltip: 'Interrupt',
                ),
                GestureDetector(
                  onTap: onMic,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: micOn ? cs.primary : cs.surfaceContainerHighest,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Icon(
                      micOn ? Icons.mic : Icons.mic_none,
                      color: micOn ? cs.onPrimary : cs.onSurfaceVariant,
                      size: 26,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {}, // placeholder for speaker toggle later
                  icon: const Icon(Icons.volume_up_outlined),
                  tooltip: 'Speaker',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
