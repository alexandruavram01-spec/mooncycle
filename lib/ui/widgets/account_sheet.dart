import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// The account actions, shared by Settings and the partner's menu.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _AccountSheet(),
  );
}

/// Asks first, then takes a test account back to "Who's this for?" with its
/// logs, quiz answers and partner connection cleared.
Future<void> confirmStartOver(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider.notifier);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Start over?'),
      content: const Text(
        'This clears the logs, quiz answers and partner connection for this '
        'account on this device, then goes back to the first question. The '
        'account itself stays.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Start over'),
        ),
      ],
    ),
  );
  if (confirmed == true) await session.startOver();
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(sessionProvider).valueOrNull ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signed in as', style: theme.textTheme.labelMedium),
            Text(email, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              subtitle: const Text('Your logs stay on this device.'),
              onTap: () async {
                // The sheet closes first; both are captured while it is open.
                final session = ref.read(sessionProvider.notifier);
                Navigator.of(context).pop();
                await session.signOut();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Delete account',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text(
                'Removes your account and erases this device.',
              ),
              onTap: () async {
                final session = ref.read(sessionProvider.notifier);
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final password = await showDialog<String>(
                  context: context,
                  builder: (_) => const _DeleteAccountDialog(),
                );
                if (password == null) return;
                navigator.pop();
                try {
                  await session.deleteAccount(password);
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your account and partner connection are removed from the '
            'server, and your logs and quiz answers are erased from this '
            'device. This cannot be undone.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_password.text.isEmpty) return;
            Navigator.of(context).pop(_password.text);
          },
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
