import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../l10n/ui.dart';

/// Shown once per account, after the quiz: what she logs lives only on
/// this phone, so uninstalling MoonCycle or losing the phone loses it,
/// unless her phone's own backup includes it. (Phones do not tell an app
/// when it is being uninstalled, so it cannot warn her at that moment.)
/// "Export my data" was removed on 31 October 2026: testers found it
/// confusing.
Future<void> showDataNotice(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.phone_android_outlined),
      title: Text(tr('Your data lives on this phone')),
      content: Text(
        tr('What you log is stored only on this phone, not on our servers. '
            'That keeps it private. Your phone\'s own backup (iCloud or your '
            'Google account) can keep a copy; without it, uninstalling '
            'MoonCycle or losing your phone means your logs cannot be '
            'recovered.'),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('I understand')),
        ),
      ],
    ),
  );
  await ref.read(dataNoticeProvider.notifier).markSeen();
}
