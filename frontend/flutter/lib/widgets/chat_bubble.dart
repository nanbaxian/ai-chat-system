import 'package:flutter/material.dart';
import 'mini_waveform.dart';

enum ChatRole { user, assistant }

class ChatBubble extends StatelessWidget {
  final ChatRole role;
  final String text;
  final bool streaming;
  final bool speaking;
  final Widget? footer;

  const ChatBubble({
    super.key,
    required this.role,
    required this.text,
    required this.streaming,
    required this.speaking,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == ChatRole.user;
    final cs = Theme.of(context).colorScheme;

    final bg = isUser ? cs.primary : cs.surfaceContainerHighest;
    final fg = isUser ? cs.onPrimary : cs.onSurface;

    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 18),
    );

    return Column(
      crossAxisAlignment: align,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: EdgeInsets.only(
              left: isUser ? 64 : 16,
              right: isUser ? 16 : 64,
              top: 10,
              bottom: 2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text.isEmpty && streaming ? ' ' : text,
                  style: TextStyle(color: fg, height: 1.35, fontSize: 15.5),
                ),
                if (!isUser) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiniWaveform(active: speaking),
                      if (footer != null) ...[
                        const SizedBox(width: 10),
                        DefaultTextStyle(
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                          child: footer!,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
