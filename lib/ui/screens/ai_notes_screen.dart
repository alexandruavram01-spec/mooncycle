import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../legal.dart';
import '../../services/api_client.dart';
import '../../state/providers.dart';
import '../widgets/links.dart';
import '../../l10n/ui.dart';

/// The AI chat: what it is, what is sent and to whom, and her explicit
/// consent before anything is. Off unless she turns it on here; nothing is
/// ticked for her.
class AiNotesScreen extends ConsumerStatefulWidget {
  const AiNotesScreen({super.key});

  @override
  ConsumerState<AiNotesScreen> createState() => _AiNotesScreenState();
}

class _AiNotesScreenState extends ConsumerState<AiNotesScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _set(bool on) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(aiNotesProvider.notifier).set(on);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on
                ? tr('AI chat is on. Tap the chat bubble on Today.')
                : tr('AI chat is off. Nothing more will be sent.'),
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = ref.watch(aiNotesProvider).value ?? false;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(tr(text), style: theme.textTheme.titleSmall),
        );
    Widget para(String text) =>
        Text(tr(text), style: theme.textTheme.bodyMedium);

    return Scaffold(
      appBar: AppBar(title: Text(tr('AI chat'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          para(
            'Ask questions about your cycle and what you have logged, in a '
            'chat on your Today screen. Each day it starts with a short '
            'message about today\'s card. The answers come from the same '
            'cards, which are based on NHS information, and from your own '
            'log, written by AI. The "See a GP" lines and Get help now stay '
            'exactly as they are. Up to 20 messages a day.',
          ),
          heading('What is sent'),
          para(
            'What you write in the chat, and a short summary worked out on '
            'your phone: the day and phase of your cycle, your estimated '
            'dates and usual lengths, today\'s card, and which symptoms you '
            'logged in the last 14 days and on how many days. Never your '
            'name, email, notes, temperature or weight.',
          ),
          heading('Who it goes to'),
          para(
            'Anthropic, the company that makes the Claude AI, in the United '
            'States. It writes the answers for us and deletes what we sent '
            'within 30 days (longer only if its safety systems flag misuse). '
            'It does not use it to train its AI. MoonCycle keeps neither your '
            'messages nor the answers on its server. Your chat history is '
            'kept only on this phone, and you can delete it from the chat.',
          ),
          heading('Good to know'),
          para(
            'The chat gives general information, not medical advice, and AI '
            'can make mistakes. It cannot diagnose anything or tell whether '
            'you are pregnant. If you don\'t feel well, use Get help now. You '
            'can turn the chat off here at any time, and nothing more is sent '
            'from then on.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => openExternal(
                context,
                Uri.parse(Legal.privacyUrl),
                'Could not open the link.',
              ),
              child: Text(tr('Privacy policy')),
            ),
          ),
          const SizedBox(height: 8),
          if (on)
            OutlinedButton(
              onPressed: _saving ? null : () => _set(false),
              child: Text(tr('Turn AI chat off')),
            )
          else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: Text(
                tr('I agree to MoonCycle sending my messages and this summary '
                    'about my health to Anthropic to answer me.'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _agreed && !_saving ? () => _set(true) : null,
              child: Text(tr('Turn on')),
            ),
          ],
        ],
      ),
    );
  }
}
