import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_key.dart';
import '../../domain/her_insights.dart';
import '../../l10n/her_insights.dart';
import '../../state/providers.dart';
import '../screens/get_help_screen.dart';
import 'links.dart';

/// Today's insight card on her Today screen, chosen on her phone in the
/// order she set: safety, what she logged, her own patterns, then general
/// information. Usually one card; two only when the first is a safety card.
class HerInsightsSection extends ConsumerWidget {
  const HerInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(herInsightsEnabledProvider)) return const SizedBox.shrink();
    final memory = ref.watch(insightMemoryProvider).valueOrNull;
    if (memory == null) return const SizedBox.shrink();

    final (picks, updated) = HerInsightPicker.choose(
      ref.watch(herInsightCandidatesProvider),
      memory,
      DayKey.today(),
    );
    // Remembers today's choice, so it stays the same all day.
    if (updated != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(insightMemoryProvider.notifier).save(updated);
        }
      });
    }
    if (picks.isEmpty) return const SizedBox.shrink();

    final texts = ref.watch(herInsightTextsProvider);
    return Column(
      children: [
        for (final pick in picks)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _InsightCard(
              key: ValueKey(pick.id),
              pick: pick,
              texts: texts,
            ),
          ),
      ],
    );
  }
}

class _InsightCard extends ConsumerWidget {
  const _InsightCard({super.key, required this.pick, required this.texts});

  final InsightCandidate pick;
  final HerInsightTexts texts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = texts.cards[pick.id];
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final safety = pick.tier == InsightTier.safety;
    final seeGp = text.seeGp;
    final helpNow = text.helpNow;
    final memory = ref.read(insightMemoryProvider.notifier);

    return Card(
      shape: safety
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: scheme.error, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _icon(pick.tier),
                  size: 18,
                  color: safety ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _label(),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: texts.ui['hide'],
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => memory.dismiss(pick.id),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(_fill(text.body), style: theme.textTheme.bodyMedium),
                  if (seeGp != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.medical_services_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(seeGp, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (helpNow != null)
              ExpansionTile(
                tilePadding: const EdgeInsets.only(right: 10),
                childrenPadding: const EdgeInsets.only(right: 10, bottom: 4),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                expandedAlignment: Alignment.centerLeft,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
                title: Text(
                  texts.ui['helpNow']!,
                  style: theme.textTheme.labelLarge,
                ),
                children: [
                  Text(helpNow, style: theme.textTheme.bodyMedium),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GetHelpScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: Text(texts.ui['openHelp']!),
                  ),
                ],
              )
            else
              const SizedBox(height: 8),
            if (text.sources.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 4),
                child: Text(texts.ui['ownLog']!, style: muted),
              )
            else
              Wrap(
                children: [
                  for (final code in text.sources)
                    if (texts.sources[code] case final source?)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => openExternal(
                          context,
                          Uri.parse(source.url),
                          texts.ui['linkFailed']!,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text('${texts.ui['source']}: ${source.name}'),
                      ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {
                  memory.markNotRelevant(pick.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(texts.ui['notRelevantDone']!)),
                  );
                },
                child: Text(texts.ui['notRelevant']!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label() {
    final symptom = pick.symptom;
    if (pick.tier == InsightTier.logged && symptom != null) {
      return texts.becauseYouLogged.replaceAll(
        '{x}',
        texts.loggedPhrase[symptom] ?? symptom.toLowerCase(),
      );
    }
    if (pick.tier == InsightTier.safety) return texts.labels['safety']!;
    return texts.labels[pick.id] ?? texts.labels[pick.tier.name] ?? '';
  }

  /// Fills in the cards built from her own log.
  String _fill(String body) {
    final pattern = pick.pattern;
    final lengths = pick.cycleLengths;
    final high = pick.energyHigh;
    final low = pick.energyLow;
    var result = body;
    if (pattern != null) {
      result = result
          .replaceAll(
            '{thing}',
            texts.patternPhrase[pattern.symptom] ??
                pattern.symptom.toLowerCase(),
          )
          .replaceAll('{when}', texts.when[pattern.phase]!)
          .replaceAll('{hits}', '${pattern.hits}')
          .replaceAll('{cycles}', '${pattern.cycles}');
    }
    if (lengths.isNotEmpty) {
      final listed = lengths.length == 1
          ? '${lengths.first}'
          : '${lengths.sublist(0, lengths.length - 1).join(', ')} '
              '${texts.ui['and']} ${lengths.last}';
      result = result.replaceAll('{lengths}', listed);
    }
    if (high != null && low != null) {
      result = result
          .replaceAll('{high}', texts.when[high]!)
          .replaceAll('{low}', texts.when[low]!);
    }
    return result;
  }

  static IconData _icon(InsightTier tier) => switch (tier) {
        InsightTier.safety => Icons.health_and_safety_outlined,
        InsightTier.logged => Icons.edit_note,
        InsightTier.history => Icons.insights,
        InsightTier.education => Icons.menu_book_outlined,
      };
}
