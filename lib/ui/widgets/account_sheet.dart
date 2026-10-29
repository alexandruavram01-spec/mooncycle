import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/account_service.dart';
import '../../services/apple_account.dart';
import '../../services/device_check.dart';
import '../../services/google_account.dart';
import '../../state/providers.dart';
import '../../l10n/ui.dart';

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
    final email = ref.watch(sessionProvider).value ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Signed in as'), style: theme.textTheme.labelMedium),
            Text(email, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: Text(tr('Sign out')),
              subtitle: Text(tr('Your logs stay on this device.')),
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
                tr('Delete account'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(
                tr('Removes your account and erases this device.'),
              ),
              onTap: () async {
                final session = ref.read(sessionProvider.notifier);
                final accounts = ref.read(accountServiceProvider);
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                _Confirmation? confirmation;
                try {
                  confirmation = await _confirmDeletion(context, accounts);
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                  return;
                }
                if (confirmation == null) return;
                navigator.pop();
                try {
                  await session.deleteAccount(
                    password: confirmation.password,
                    googleIdToken: confirmation.googleIdToken,
                    appleIdentityToken: confirmation.appleIdentityToken,
                  );
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

/// How deleting was confirmed: by the phone's own lock, by password, or for
/// accounts made with Google or Apple, by them.
class _Confirmation {
  const _Confirmation.byDevice()
      : password = null,
        googleIdToken = null,
        appleIdentityToken = null;
  const _Confirmation.byPassword(String this.password)
      : googleIdToken = null,
        appleIdentityToken = null;
  const _Confirmation.byGoogle(String this.googleIdToken)
      : password = null,
        appleIdentityToken = null;
  const _Confirmation.byApple(String this.appleIdentityToken)
      : password = null,
        googleIdToken = null;

  /// All null when the phone's lock confirmed it.
  final String? password;
  final String? googleIdToken;
  final String? appleIdentityToken;
}

/// Asks first, then checks it is the owner, so a borrowed, unlocked phone is
/// not enough: the phone's fingerprint, face or PIN where it has a lock;
/// otherwise (and on the website) the password, or Google's account picker
/// for accounts made with Google. Null if cancelled.
Future<_Confirmation?> _confirmDeletion(
  BuildContext context,
  AccountService accounts,
) async {
  if (await DeviceCheck.available()) {
    if (!context.mounted) return null;
    final go = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(step: _NextStep.deviceLock),
    );
    if (go == null) return null;
    switch (await DeviceCheck.confirm(
      tr('Confirm it is you to delete your MoonCycle account.'),
    )) {
      case DeviceCheckResult.passed:
        return const _Confirmation.byDevice();
      case DeviceCheckResult.cancelled:
        return null;
      case DeviceCheckResult.unavailable:
        break; // Falls back to the password, or Google.
    }
  }
  final method = GoogleAccount.available || AppleAccount.available
      ? await accounts.signInMethod()
      : SignInMethod.password;
  if (method == SignInMethod.google && GoogleAccount.available) {
    if (!context.mounted) return null;
    final go = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(step: _NextStep.google),
    );
    if (go == null) return null;
    final token = await GoogleAccount.idToken();
    return token == null ? null : _Confirmation.byGoogle(token);
  }
  if (method == SignInMethod.apple && AppleAccount.available) {
    if (!context.mounted) return null;
    final go = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(step: _NextStep.apple),
    );
    if (go == null) return null;
    final credential = await AppleAccount.credential();
    return credential == null
        ? null
        : _Confirmation.byApple(credential.identityToken);
  }
  if (!context.mounted) return null;
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(step: _NextStep.password),
  );
  return password == null ? null : _Confirmation.byPassword(password);
}

/// How the dialog's "Delete account" is confirmed next.
enum _NextStep { deviceLock, password, google, apple }

/// Returns the password, or an empty string when the phone's lock or Google
/// checks it next. Null if cancelled.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.step});

  final _NextStep step;

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
      title: Text(tr('Delete your account?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Your account and partner connection are removed from the '
            'server, and your logs and quiz answers are erased from this '
            'device. This cannot be undone.'),
          ),
          const SizedBox(height: 16),
          switch (widget.step) {
            _NextStep.password => TextField(
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr('Password'),
                  border: OutlineInputBorder(),
                ),
              ),
            _NextStep.deviceLock => Text(
                tr('Next, your phone asks for your fingerprint, face or PIN.'),
              ),
            _NextStep.google => Text(
                tr('Next, choose your Google account to confirm it is you.'),
              ),
            _NextStep.apple => Text(
                tr('Next, confirm with your Apple account that it is you.'),
              ),
          },
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (widget.step != _NextStep.password) {
              Navigator.of(context).pop('');
              return;
            }
            if (_password.text.isEmpty) return;
            Navigator.of(context).pop(_password.text);
          },
          child: Text(tr('Delete account')),
        ),
      ],
    );
  }
}
