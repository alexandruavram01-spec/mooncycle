import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/links.dart';

/// Where to get help, always one tap away: from the Today screen's top bar,
/// from Settings, and from any card with urgent advice. Crisis help lives
/// here rather than being pushed at her because of a mood she logged.
class GetHelpScreen extends ConsumerWidget {
  const GetHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final texts = ref.watch(herInsightTextsProvider);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final failed = texts.ui['linkFailed']!;

    return Scaffold(
      appBar: AppBar(title: Text(texts.ui['openHelp']!)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(texts.helpIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          for (final option in texts.help)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(option.body, style: theme.textTheme.bodyMedium),
                    if (option.phone != null || option.link != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (option.phone case final phone?)
                            FilledButton.icon(
                              onPressed: () => openExternal(
                                context,
                                Uri(scheme: 'tel', path: phone),
                                failed,
                              ),
                              icon: const Icon(Icons.call),
                              label: Text(option.callLabel ?? phone),
                            ),
                          if (option.link case final link?)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  openExternal(context, Uri.parse(link), failed),
                              icon: const Icon(Icons.open_in_new),
                              label: Text(option.linkLabel ?? link),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(texts.helpOutside, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final code in texts.helpSources)
            if (texts.sources[code] case final source?)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () =>
                      openExternal(context, Uri.parse(source.url), failed),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    '${texts.ui['source']}: ${source.name}',
                    style: muted,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
