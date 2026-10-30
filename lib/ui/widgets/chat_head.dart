import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_key.dart';
import '../../state/providers.dart';
import '../../l10n/ui.dart';
import '../screens/her_chat_screen.dart';

/// The round chat bubble on her Today screen, like the chat heads messaging
/// apps used to float over the screen: she can drag it up and down, and to
/// either side, where it settles against the edge. A dot shows while
/// today's message is waiting. Only while the AI chat is on.
class ChatHead extends ConsumerStatefulWidget {
  const ChatHead({super.key});

  @override
  ConsumerState<ChatHead> createState() => _ChatHeadState();
}

class _ChatHeadState extends ConsumerState<ChatHead> {
  static const _size = 58.0;
  static const _margin = 12.0;

  /// Where it rests, kept while the app is open: the side, and how far
  /// down as a share of the space it can move in.
  static bool _right = true;
  static double _down = 0.62;

  /// While dragging, its top-left corner.
  Offset? _dragging;

  @override
  Widget build(BuildContext context) {
    if (!(ref.watch(aiNotesProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final history = ref.watch(herChatProvider).value;
    final unread = history?.unread(DayKey.today()) ?? false;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, box) {
        final maxX = box.maxWidth - _size - _margin;
        final maxY = box.maxHeight - _size - _margin;
        final rest = Offset(_right ? maxX : _margin, _margin + _down * (maxY - _margin));
        final at = _dragging ?? rest;

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragging == null
                  ? const Duration(milliseconds: 220)
                  : Duration.zero,
              curve: Curves.easeOutBack,
              left: at.dx,
              top: at.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _dragging = at),
                onPanUpdate: (d) => setState(() {
                  final next = (_dragging ?? at) + d.delta;
                  _dragging = Offset(
                    next.dx.clamp(_margin, maxX),
                    next.dy.clamp(_margin, maxY),
                  );
                }),
                onPanEnd: (_) => setState(() {
                  final end = _dragging ?? at;
                  _right = end.dx + _size / 2 > box.maxWidth / 2;
                  _down = maxY > _margin
                      ? ((end.dy - _margin) / (maxY - _margin)).clamp(0.0, 1.0)
                      : 0;
                  _dragging = null;
                }),
                child: Semantics(
                  button: true,
                  label: unread
                      ? tr('Open the AI chat. A new message is waiting.')
                      : tr('Open the AI chat'),
                  child: Material(
                    color: scheme.primary,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: scheme.shadow,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const HerChatScreen(),
                        ),
                      ),
                      child: SizedBox(
                        width: _size,
                        height: _size,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_rounded,
                              color: scheme.onPrimary,
                              size: 28,
                            ),
                            Icon(
                              Icons.auto_awesome,
                              color: scheme.primary,
                              size: 13,
                            ),
                            if (unread)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: scheme.error,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: scheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
