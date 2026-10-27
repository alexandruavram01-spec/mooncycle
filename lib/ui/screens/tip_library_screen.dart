import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../domain/profile.dart';
import '../../l10n/partner_messages.dart';
import '../../services/tip_library_service.dart';
import '../../state/providers.dart';
import '../../l10n/ui.dart';

final _ratingsProvider = FutureProvider.autoDispose<Map<String, TipRating>>(
  (ref) async {
    final ratings = await ref.watch(tipLibraryServiceProvider).ratings();
    return {for (final rating in ratings) rating.code: rating};
  },
);

/// The editor's view of the daily partner tips: how people rated each one,
/// and the ones someone flagged "not okay", which nobody gets until they are
/// put back here.
///
/// The wording itself is fixed in the app (`lib/l10n/`), reviewed through
/// the files in `content/`.
class TipLibraryScreen extends ConsumerStatefulWidget {
  const TipLibraryScreen({super.key, this.initialFilter = 'pulled'});

  /// `pulled`, `rated` or `all`.
  final String initialFilter;

  @override
  ConsumerState<TipLibraryScreen> createState() => _TipLibraryScreenState();
}

class _TipLibraryScreenState extends ConsumerState<TipLibraryScreen> {
  static const _filters = [
    ('pulled', 'Pulled'),
    ('rated', 'Rated'),
    ('all', 'All'),
  ];

  static const _emptyText = {
    'pulled': 'Nothing has been flagged as not okay.',
    'rated': 'No ratings yet.',
    'all': 'No tips.',
  };

  late String _filter = widget.initialFilter;

  Future<void> _restore(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tipLibraryServiceProvider).restore(code);
      if (!mounted) return;
      ref
        ..invalidate(_ratingsProvider)
        ..invalidate(pulledTipsProvider);
      messenger.showSnackBar(SnackBar(content: Text('$code is back.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  static bool _matches(String filter, TipRating? rating) => switch (filter) {
        'pulled' => rating?.pulled ?? false,
        'rated' => rating != null &&
            rating.likes + rating.notFunny + rating.notOkay > 0,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final messages = ref.watch(partnerMessagesProvider);
    final language = ref.watch(languageProvider).valueOrNull;
    final ratings = ref.watch(_ratingsProvider);
    final tips = messages.allTips.toList();

    int count(String filter) {
      final byCode = ratings.valueOrNull ?? const {};
      return tips.where((t) => _matches(filter, byCode[t.$3.id])).length;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Tip library')),
        actions: [
          IconButton(
            tooltip: tr('Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_ratingsProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Every daily tip a partner can get'
            '${language == null ? '' : ', in ${language.label}'}. Ratings '
            'come from partners and from her "Today\'s tip for your partner" '
            'card. A "not okay" hides a tip for everyone until you put it '
            'back.',
            style: muted,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (filter, name) in _filters)
                ChoiceChip(
                  label: Text(
                    ratings.hasValue ? '$name · ${count(filter)}' : name,
                  ),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ratings.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (byCode) {
              final shown = [
                for (final tip in tips)
                  if (_matches(_filter, byCode[tip.$3.id])) tip,
              ];
              if (shown.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_emptyText[_filter]!, style: muted),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final phase in [...CyclePhase.values, null])
                    ..._group(context, messages, phase, shown, byCode),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// One phase's tips under a heading, in cycle order, plain to funniest.
  List<Widget> _group(
    BuildContext context,
    PartnerMessages messages,
    CyclePhase? phase,
    List<(CyclePhase?, PartnerTone, Line)> shown,
    Map<String, TipRating> byCode,
  ) {
    final theme = Theme.of(context);
    final group = [
      for (final tone in PartnerTone.values)
        ...shown.where((t) => t.$1 == phase && t.$2 == tone),
    ];
    if (group.isEmpty) return const [];
    final heading =
        phase == null ? 'Any phase' : messages.cards[phase]!.name;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          '$heading · ${group.length}',
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
      for (final (_, tone, line) in group)
        _TipCard(
          line: line,
          tone: tone,
          rating: byCode[line.id],
          onRestore: () => _restore(line.id),
        ),
    ];
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.line,
    required this.tone,
    required this.rating,
    required this.onRestore,
  });

  final Line line;
  final PartnerTone tone;
  final TipRating? rating;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rating = this.rating;
    final pulled = rating?.pulled ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.text, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 6),
              Text('${line.id} · ${tone.label}', style: muted),
              if (rating != null)
                Text(
                  '${rating.likes} nice · ${rating.notFunny} not funny · '
                  '${rating.notOkay} not okay',
                  style: muted,
                ),
              if (pulled) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Pulled: nobody gets this tip.'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: onRestore,
                      child: Text(tr('Put back')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
