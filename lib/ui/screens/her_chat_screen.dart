import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/day_key.dart';
import '../../domain/her_chat.dart';
import '../../state/providers.dart';
import '../../l10n/ui.dart';
import 'ai_notes_screen.dart';
import 'get_help_screen.dart';

/// Whether an answer is on its way, kept outside the screen so leaving and
/// coming back still shows it.
class HerChatBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool busy) => state = busy;
}

final herChatBusyProvider =
    NotifierProvider<HerChatBusy, bool>(HerChatBusy.new);

/// Today's first message: today's AI-written note when there is one, else
/// today's card, else where she is in her cycle; then whether she wants to
/// know more.
ChatMessage todaysOpener(WidgetRef ref) {
  final today = DayKey.today();
  final now = DateTime.now();
  final memory = ref.read(insightMemoryProvider).value;
  final texts = ref.read(herInsightTextsProvider);
  final status = ref.read(cycleStatusProvider);
  final ids = memory != null && memory.pickDay == today
      ? memory.pickIds
      : const <String>[];
  final more = [tr('Yes, tell me more')];

  for (final id in ids) {
    final note = memory!.pickNotes[id];
    if (note != null && note.isNotEmpty) {
      return ChatMessage(
        fromHer: false,
        text: '$note\n\n${tr('Want to know more about it?')}',
        at: now,
        ai: true,
        opener: true,
        suggestions: more,
      );
    }
  }
  if (ids.isNotEmpty) {
    final id = ids.first;
    final card = texts.cards[memory!.pickWording[id] ?? id] ?? texts.cards[id];
    if (card != null && !card.title.contains('{')) {
      return ChatMessage(
        fromHer: false,
        text: trf(
          'Today\'s note is about "{title}". Want to know more about it?',
          {'title': card.title},
        ),
        at: now,
        opener: true,
        suggestions: more,
      );
    }
  }
  if (status != null && status.hasData) {
    return ChatMessage(
      fromHer: false,
      text: trf(
        'You\'re on day {n} of your cycle, in the {phase} phase. Want to know '
        'more about what that can mean?',
        {'n': status.dayOfCycle, 'phase': tr(status.phase.label).toLowerCase()},
      ),
      at: now,
      opener: true,
      suggestions: more,
    );
  }
  return ChatMessage(
    fromHer: false,
    text: tr(
      'Hi. You can ask me about your cycle or anything you have logged. '
      'What would you like to know?',
    ),
    at: now,
    opener: true,
  );
}

/// Her AI chat. Its history is kept only on this phone.
class HerChatScreen extends ConsumerStatefulWidget {
  const HerChatScreen({super.key});

  @override
  ConsumerState<HerChatScreen> createState() => _HerChatScreenState();
}

class _HerChatScreenState extends ConsumerState<HerChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int? _remaining;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted || !(ref.read(aiNotesProvider).value ?? false)) return;
    await ref.read(herChatProvider.future);
    if (!mounted) return;
    await ref.read(herChatProvider.notifier).open(() => todaysOpener(ref));
    _toBottom();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || ref.read(herChatBusyProvider)) return;
    _input.clear();
    final busy = ref.read(herChatBusyProvider.notifier);
    busy.set(true);
    _toBottom();
    try {
      final today = DayKey.today();
      final memory = ref.read(insightMemoryProvider).value;
      final summary = herChatContext(
        today: today,
        status: ref.read(cycleStatusProvider),
        logs: ref.read(logsProvider).value ?? const [],
        profile: ref.read(profileProvider),
        card: memory != null &&
                memory.pickDay == today &&
                memory.pickIds.isNotEmpty
            ? memory.pickIds.first
            : null,
      );
      final remaining = await ref.read(herChatProvider.notifier).send(
            message,
            language: UiText.romanian ? 'ro' : 'en',
            context: summary,
          );
      if (mounted && remaining != null) setState(() => _remaining = remaining);
    } finally {
      busy.set(false);
      _toBottom();
    }
  }

  Future<void> _report(ChatMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Report this answer?')),
        content: Text(
          tr('It is sent to MoonCycle without your name or your messages, so '
              'we can check it.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Report')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final sent = await ref.read(herChatProvider.notifier).report(message);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? tr('Thank you. We will check this answer.')
              : tr('Could not send the report. Try again later.'),
        ),
      ),
    );
  }

  Future<void> _deleteHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete your chat history?')),
        content: Text(
          tr('Every message is removed from this phone. This cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(herChatProvider.notifier).clear();
    await _open();
  }

  void _openHelp() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GetHelpScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = ref.watch(aiNotesProvider).value ?? false;
    final history = ref.watch(herChatProvider).value ?? const ChatHistory();
    final busy = ref.watch(herChatBusyProvider);
    final helpLabel = ref.watch(herInsightTextsProvider).ui['openHelp']!;
    ref.listen(herChatProvider, (previous, next) => _toBottom());

    final messages = history.messages;
    final today = DayKey.today();
    final last = messages.isEmpty ? null : messages.last;
    final chips = !busy &&
            last != null &&
            !last.fromHer &&
            last.day == today &&
            last.notice == null
        ? last.suggestions
        : const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('MoonCycle chat')),
            Text(
              tr('AI · general information, not medical advice'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: helpLabel,
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: _openHelp,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteHistory();
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiNotesScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Text(tr('Delete chat history')),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text(tr('AI chat settings')),
              ),
            ],
          ),
        ],
      ),
      body: !on
          ? _ChatOff()
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: messages.length + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) return const _Disclaimer();
                      if (i == messages.length + 1) {
                        return busy
                            ? const _Typing()
                            : const SizedBox(height: 4);
                      }
                      final message = messages[i - 1];
                      final previous = i >= 2 ? messages[i - 2] : null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (previous == null || previous.day != message.day)
                            _DayDivider(day: message.day),
                          _Bubble(
                            message: message,
                            helpLabel: helpLabel,
                            onHelp: _openHelp,
                            onReport: () => _report(message),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (chips.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final chip in chips)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(chip),
                              onPressed: () => _send(chip),
                            ),
                          ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                focusNode: _focus,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 500,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.send,
                                onSubmitted: _send,
                                decoration: InputDecoration(
                                  hintText: tr('Ask about your cycle…'),
                                  counterText: '',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filled(
                              tooltip: tr('Send'),
                              onPressed: busy || _remaining == 0
                                  ? null
                                  : () => _send(_input.text),
                              icon: const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                        if (_remaining != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 4),
                            child: Text(
                              trCount(
                                _remaining!,
                                '{n} message left today',
                                '{n} messages left today',
                              ),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChatOff extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('AI chat is off.'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiNotesScreen(),
                  ),
                ),
                child: Text(tr('Enable AI chat')),
              ),
            ],
          ),
        ),
      );
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        tr('Answers are written by AI from MoonCycle\'s reviewed notes and '
            'your log. They are general information, not medical advice. '
            'Your chat is kept only on this phone.'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});

  final DayKey day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DayKey.today();
    final label = day == today
        ? tr('Today')
        : day == today.addDays(-1)
            ? tr('Yesterday')
            : DateFormat.MMMd(UiText.romanian ? 'ro' : 'en_GB')
                .format(DateTime(day.year, day.month, day.day));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.helpLabel,
    required this.onHelp,
    required this.onReport,
  });

  final ChatMessage message;
  final String helpLabel;
  final VoidCallback onHelp;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hers = message.fromHer;
    final text = switch (message.notice) {
      ChatNotice.failed => tr(
          'Sorry, I could not answer just now. Check your connection and try '
          'again.',
        ),
      ChatNotice.limit => tr(
          'That was today\'s last message. The chat is back tomorrow.',
        ),
      null => message.text,
    };
    final muted =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Align(
      alignment: hers ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                hers ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: hers
                      ? scheme.primary
                      : message.urgent
                          ? scheme.errorContainer
                          : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(hers ? 18 : 4),
                    bottomRight: Radius.circular(hers ? 4 : 18),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hers
                          ? scheme.onPrimary
                          : message.urgent
                              ? scheme.onErrorContainer
                              : scheme.onSurface,
                      fontStyle: message.notice != null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
              ),
              if (message.urgent)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: onHelp,
                    icon: const Icon(Icons.phone_in_talk_outlined, size: 18),
                    label: Text(helpLabel),
                  ),
                ),
              if (message.ai)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(tr('Written by AI'), style: muted),
                    if (message.reported) ...[
                      const SizedBox(width: 8),
                      Text(tr('Reported'), style: muted),
                    ] else
                      IconButton(
                        tooltip: tr('Report this answer'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: scheme.onSurfaceVariant,
                        onPressed: onReport,
                        icon: const Icon(Icons.flag_outlined),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three dots while the answer is on its way.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Semantics(
          label: tr('Writing an answer'),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: ((_controller.value * 3 - i) % 3) < 1 ? 1.0 : 0.3,
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: scheme.onSurfaceVariant,
                      ),
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
