import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../legal.dart';
import '../../services/api_client.dart';
import '../../state/providers.dart';
import '../widgets/links.dart';
import '../../l10n/ui.dart';

/// AI-written notes: what they are, what is sent and to whom, and her
/// explicit consent before anything is. Off unless she turns them on here.
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
                ? tr('AI-written notes are on.')
                : tr('AI-written notes are off. Nothing more will be sent.'),
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
      appBar: AppBar(title: Text(tr('AI-written notes'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          para(
            'Instead of the standard wording, MoonCycle can write your daily '
            'card as a short note around your own log, using AI. What it says '
            'still comes from the same card, which is based on NHS '
            'information. The "See a GP" line and where to get help stay '
            'exactly as they are.',
          ),
          heading('What is sent'),
          para(
            'The card chosen for you that day, and a short summary worked out '
            'on your phone: the symptom the card is about, patterns in your '
            'recorded cycles and estimated dates. Never your name, email, '
            'notes or the rest of what you logged.',
          ),
          heading('Who it goes to'),
          para(
            'Anthropic, the company that makes the Claude AI, in the United '
            'States. It writes the note for us and deletes what we sent '
            'within 30 days (longer only if its safety systems flag misuse). '
            'It does not use it to train its AI. MoonCycle keeps neither the '
            'summary nor the note on its server.',
          ),
          heading('Good to know'),
          para(
            'The notes are general information, not medical advice, and AI '
            'can make mistakes. If you don\'t feel well, use Get help now. '
            'You can turn the notes off here at any time, and nothing more '
            'is sent from then on.',
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
              child: Text(tr('Turn AI-written notes off')),
            )
          else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              title: Text(
                tr('I agree to MoonCycle sending this summary about my health to '
                'Anthropic to write my notes.'),
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
