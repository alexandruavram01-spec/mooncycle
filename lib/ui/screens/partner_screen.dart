import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/partner_link_service.dart';
import '../../state/providers.dart';
import '../../l10n/ui.dart';
import 'partner_chat_screen.dart';

class PartnerScreen extends ConsumerWidget {
  const PartnerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sharing = settings.sharing;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Partner'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Share with a partner'),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    tr('They see a summary you choose — never your raw logs. '
                    'You can turn it off at any time and they lose access '
                    'immediately.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: sharing.enabled,
                    title: Text(tr('Sharing on')),
                    onChanged: (v) async {
                      // Turning sharing off disconnects him; connecting
                      // again later is a new (paid) connection, so she is
                      // told first.
                      if (!v && (ref.read(pairingProvider).value?.linked ??
                          false)) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(tr('Turn sharing off?')),
                            content: Text(
                              tr('Your partner is disconnected straight away '
                                  'and your chat with them is deleted. Your '
                                  'first partner connection was free; '
                                  'connecting again will be a one-time '
                                  'payment.'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: Text(tr('Cancel')),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(tr('Turn off')),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }
                      await ref
                          .read(settingsProvider.notifier)
                          .updateSharing(sharing.copyWith(enabled: v));
                    },
                  ),
                ],
              ),
            ),
          ),
          if (sharing.enabled) ...[
            const SizedBox(height: 16),
            const _PairingCard(),
            const PartnerChatButton(),
            const SizedBox(height: 8),
            Text(
              tr('Nudges to them and their offers to you are on the Today tab.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(tr('What they can see'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            _ShareToggle(
              label: tr('Cycle phase and support tips'),
              value: sharing.sharePhase,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSharing(sharing.copyWith(sharePhase: v)),
            ),
            _ShareToggle(
              label: tr('Days until next period'),
              value: sharing.shareNextPeriodDate,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSharing(sharing.copyWith(shareNextPeriodDate: v)),
            ),
            // The older single "Today's symptoms" and "Energy level" switches
            // are cleared whenever these change, so they can't keep sharing
            // in the background.
            _ShareToggle(
              label: tr('Mood'),
              subtitle: tr('The mood and energy you log for the day.'),
              value: sharing.shareMood || sharing.shareSymptoms,
              onChanged: (v) => ref.read(settingsProvider.notifier).updateSharing(
                    sharing.copyWith(
                      shareMood: v,
                      sharePain: sharing.sharePain || sharing.shareSymptoms,
                      shareSymptoms: false,
                      shareEnergy: false,
                    ),
                  ),
            ),
            _ShareToggle(
              label: tr('Pain and discomfort'),
              subtitle: tr('The pain and discomfort you log for the day.'),
              value: sharing.sharePain || sharing.shareSymptoms,
              onChanged: (v) => ref.read(settingsProvider.notifier).updateSharing(
                    sharing.copyWith(
                      sharePain: v,
                      shareMood: sharing.shareMood || sharing.shareSymptoms,
                      shareSymptoms: false,
                      shareEnergy: false,
                    ),
                  ),
            ),
            _ShareToggle(
              label: tr('Support requests'),
              subtitle: tr('Lets you send nudges like "I need a hug" from the '
                  'Today tab.'),
              value: sharing.allowRequests,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSharing(sharing.copyWith(allowRequests: v)),
            ),
            _ShareToggle(
              label: tr('Fertile window'),
              subtitle: tr('Off by default — the most sensitive thing here.'),
              value: sharing.shareFertileWindow,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSharing(sharing.copyWith(shareFertileWindow: v)),
            ),
            _ShareToggle(
              label: tr('Let their tips be funny'),
              subtitle: tr('Jokes switch off on their own on days you log as '
                  'rough, and when your period is late.'),
              value: sharing.allowJokes,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSharing(sharing.copyWith(allowJokes: v)),
            ),
            if (sharing.allowJokes)
              _ShareToggle(
                label: tr('Humour during my period too'),
                subtitle: tr('Off unless you turn it on. Their tips stay plain '
                    'during your period otherwise.'),
                value: sharing.allowPeriodHumour,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSharing(sharing.copyWith(allowPeriodHumour: v)),
              ),
          ],
        ],
      ),
    );
  }
}

class _ShareToggle extends StatelessWidget {
  const _ShareToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        dense: true,
      );
}

class _PairingCard extends ConsumerWidget {
  const _PairingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pairing = ref.watch(pairingProvider);

    Future<void> issueNewCode({bool continueFree = false}) async {
      try {
        await ref
            .read(partnerLinkServiceProvider)
            .newCode(continueFree: continueFree);
      } on PairingPaymentNeeded {
        // The card shows the payment screen after the refresh below.
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      if (context.mounted) ref.invalidate(pairingProvider);
    }

    // Disconnecting always works: the link, the snapshot and their chat go
    // from the server. Connecting again then uses a new connection.
    Future<void> disconnect() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Disconnect your partner?')),
          content: Text(
            tr('They stop seeing your summary straight away, and your chat '
                'with them is deleted. Your first partner connection was '
                'free; connecting again will be a one-time payment.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Disconnect')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(partnerLinkServiceProvider).revoke();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      if (context.mounted) ref.invalidate(pairingProvider);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Pairing'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            pairing.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => e is PairingPaymentNeeded
                  ? _PaymentNeeded(
                      onContinue: () => issueNewCode(continueFree: true),
                    )
                  : Row(
                children: [
                  Expanded(child: Text('$e')),
                  IconButton(
                    tooltip: tr('Try again'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(pairingProvider),
                  ),
                ],
              ),
              data: (state) {
                final code = state.code;
                if (state.linked || code == null) {
                  return Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Your partner is connected.')),
                      ),
                      TextButton(
                        onPressed: disconnect,
                        child: Text(tr('Disconnect')),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            code,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(letterSpacing: 4),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('Copy'),
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(tr('Code copied'))),
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: tr('Generate a new code'),
                          icon: const Icon(Icons.refresh),
                          onPressed: issueNewCode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Give this code to your partner. It works once and '
                      'expires after 24 hours.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(pairingProvider),
                      child: Text(tr('Check if they have connected')),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Her free partner connection is used. Connecting again will be a one-time
/// payment for a new pairing code; until payments exist, she continues for
/// free. Nothing is chosen for her.
class _PaymentNeeded extends StatefulWidget {
  const _PaymentNeeded({required this.onContinue});

  final Future<void> Function() onContinue;

  @override
  State<_PaymentNeeded> createState() => _PaymentNeededState();
}

class _PaymentNeededState extends State<_PaymentNeeded> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.favorite_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Connect a partner again'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tr('Your first partner connection was free. Connecting again is a '
              'one-time payment for a new pairing code.'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Text(
          tr('While MoonCycle is new, it is free.'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onContinue();
                  if (mounted) setState(() => _busy = false);
                },
          child: Text(tr('Continue for free')),
        ),
      ],
    );
  }
}
