import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../services/data_export.dart';
import '../../state/providers.dart';

/// Opens the share sheet with her logs and quiz answers, so she can keep a
/// copy in Drive, email or her files.
Future<void> exportMyData(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final logs = await ref.read(logsProvider.future);
  final settings =
      ref.read(settingsProvider).valueOrNull ?? const AppSettings();
  try {
    final saved = await DataExport.share(logs, settings);
    if (saved) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Your data was saved.')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not export your data: $e')),
    );
  }
}

/// Shown once per account, after the quiz: what she logs lives only on
/// this phone, so uninstalling MoonCycle or losing the phone loses it.
/// (Phones do not tell an app when it is being uninstalled, so it cannot
/// warn her at that moment.)
Future<void> showDataNotice(BuildContext context, WidgetRef ref) async {
  final export = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.phone_android_outlined),
      title: const Text('Your data lives on this phone'),
      content: const Text(
        'What you log is stored only on this phone, not on our servers. '
        'That keeps it private, but if you uninstall MoonCycle or lose your '
        'phone, your logs cannot be recovered.\n\n'
        'You can save a copy at any time: Settings, then Export my data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Export now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('I understand'),
        ),
      ],
    ),
  );
  await ref.read(dataNoticeProvider.notifier).markSeen();
  if (export == true && context.mounted) await exportMyData(context, ref);
}
