import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/device_check.dart';
import '../../state/providers.dart';

/// The account actions, shared by Settings and the partner's menu.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _AccountSheet(),
  );
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
                final confirmation = await _confirmDeletion(context);
                if (confirmation == null) return;
                navigator.pop();
                try {
                  await session.deleteAccount(password: confirmation.password);
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

/// How deleting was confirmed: by the phone's own lock, or by password.
class _Confirmation {
  const _Confirmation.byDevice() : password = null;
  const _Confirmation.byPassword(String this.password);

  /// Null when the phone's lock confirmed it.
  final String? password;
}

/// Asks first, then checks it is the owner, so a borrowed, unlocked phone is
/// not enough: the phone's fingerprint, face or PIN where it has a lock, the
/// password otherwise (and on the website). Null if cancelled.
Future<_Confirmation?> _confirmDeletion(BuildContext context) async {
  if (await DeviceCheck.available()) {
    if (!context.mounted) return null;
    final go = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(askPassword: false),
    );
    if (go == null) return null;
    switch (await DeviceCheck.confirm(
      'Confirm it is you to delete your MoonCycle account.',
    )) {
      case DeviceCheckResult.passed:
        return const _Confirmation.byDevice();
      case DeviceCheckResult.cancelled:
        return null;
      case DeviceCheckResult.unavailable:
        break; // Falls back to the password.
    }
  }
  if (!context.mounted) return null;
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(askPassword: true),
  );
  return password == null ? null : _Confirmation.byPassword(password);
}

/// Returns the password, or an empty string when [askPassword] is false and
/// the phone's lock is checked next. Null if cancelled.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.askPassword});

  final bool askPassword;

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
          if (widget.askPassword)
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            )
          else
            const Text(
              'Next, your phone asks for your fingerprint, face or PIN.',
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
            if (!widget.askPassword) {
              Navigator.of(context).pop('');
              return;
            }
            if (_password.text.isEmpty) return;
            Navigator.of(context).pop(_password.text);
          },
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
