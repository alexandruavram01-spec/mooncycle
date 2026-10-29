import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/her_insights.dart';
import '../../l10n/her_insights.dart';
import '../../state/providers.dart';
import '../screens/ai_notes_screen.dart';
import '../screens/get_help_screen.dart';
import 'links.dart';
import '../../l10n/ui.dart';

/// Today's insight card on her Today screen, chosen on her phone in the
/// reviewed order: safety, what she logged, her own patterns, then moments
/// in her cycle and general information. Usually one card; two only when
/// the first is a safety card; none on a day with nothing new to say.
class HerInsightsSection extends ConsumerWidget {
  const HerInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(herInsightsEnabledProvider)) return const SizedBox.shrink();
    final memory = ref.watch(insightMemoryProvider).value;
    if (memory == null) return const SizedBox.shrink();

    final today = DayKey.today();
    final (picks, updated) = HerInsightPicker.choose(
      ref.watch(herInsightCandidatesProvider),
      memory,
      today,
    );
    final notifier = ref.read(insightMemoryProvider.notifier);
    // Remembers today's choice, so it stays the same all day.
    if (updated != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) notifier.save(updated);
      });
    }
    if (picks.isEmpty) return const SizedBox.shrink();

    // With AI-written notes on, today's note is asked for once; the card
    // shows as it is until it arrives, or if it never does.
    final aiNotes = ref.watch(aiNotesProvider).value ?? false;
    if (aiNotes && updated == null) {
      final profile = ref.read(profileProvider);
      for (final pick in picks) {
        if (!aiNoteEligible(pick) || memory.pickNotes.containsKey(pick.id)) {
          continue;
        }
        final request = herNoteRequest(
          pick,
          today: today,
          profile: profile,
          language: UiText.romanian ? 'ro' : 'en',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) notifier.fetchNote(pick, request);
        });
      }
    }

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
              // An empty note marks one she reported: the card shows instead.
              note: aiNotes && (memory.pickNotes[pick.id]?.isNotEmpty ?? false)
                  ? memory.pickNotes[pick.id]
                  : null,
            ),
          ),
        // Offered where the notes appear, not only in Settings. Opens the
        // same explanation and consent screen; nothing is ticked for her.
        if (!aiNotes && picks.any(aiNoteEligible))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiNotesScreen(),
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 20),
              label: Text(tr('Turn on AI-written notes')),
            ),
          ),
      ],
    );
  }
}

class _InsightCard extends ConsumerWidget {
  const _InsightCard({
    super.key,
    required this.pick,
    required this.texts,
    this.note,
  });

  final InsightPick pick;
  final HerInsightTexts texts;

  /// Her AI-written note, shown in place of the opening line and the card's
  /// words. The GP line, the urgent-help line and the sources stay as
  /// reviewed.
  final String? note;

  /// Cards about desire, where "Not feeling well?" would read oddly.
  static const _noSignpost = {'L19', 'C08'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A second wording keeps the first one's advice unless it has its own.
    final base = texts.cards[pick.id];
    final text = texts.cards[pick.wording] ?? base;
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final safety = pick.tier == InsightTier.safety;
    final seeGp = text.seeGp ?? base?.seeGp;
    final helpNow = text.helpNow ?? base?.helpNow;
    final opening = _opening();
    final sources = {
      ...text.sources,
      // The fertile-window line carries its own sources.
      if (pick.opening?.id == 'P12') ...['S7', 'S39'],
    };
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
                  if (note case final written?) ...[
                    const SizedBox(height: 6),
                    Text(written, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(texts.ui['aiNote']!, style: muted),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _report(context, memory),
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        label: Text(texts.ui['reportNote']!),
                      ),
                    ),
                  ] else ...[
                    if (opening != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        opening,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(_fill(text.body), style: theme.textTheme.bodyMedium),
                  ],
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
            // Where to turn if she doesn't feel well, always visible, rather
            // than detailed warning signs: on the safety card, on any card
            // with urgent text, and on cards about something she logged.
            if (helpNow != null ||
                safety ||
                (pick.tier == InsightTier.logged &&
                    !_noSignpost.contains(pick.id)))
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.phone_in_talk_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            texts.ui['signpost']!,
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const GetHelpScreen(),
                              ),
                            ),
                            child: Text(texts.ui['openHelp']!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10, bottom: 4),
                child: Text(texts.ui['ownLog']!, style: muted),
              )
            else
              Wrap(
                spacing: 16,
                children: [
                  for (final code in sources)
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

  /// Reports this AI-written note from inside the app, after asking.
  Future<void> _report(
    BuildContext context,
    InsightMemoryNotifier memory,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(texts.ui['reportNoteTitle']!),
        content: Text(texts.ui['reportNoteBody']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(texts.ui['cancel']!),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(texts.ui['report']!),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final sent = await memory.reportNote(pick.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          texts.ui[sent ? 'reportNoteDone' : 'reportNoteFailed']!,
        ),
      ),
    );
  }

  String _label() {
    final candidate = pick.candidate;
    final symptom = candidate.symptom;
    if (candidate.tier == InsightTier.safety) return texts.labels['safety']!;
    if (symptom != null) {
      String phrase(String s) => texts.loggedPhrase[s] ?? s.toLowerCase();
      final also = candidate.alsoLogged;
      return texts.becauseYouLogged.replaceAll(
        '{x}',
        also == null
            ? phrase(symptom)
            : '${phrase(symptom)} ${texts.ui['and']} ${phrase(also)}',
      );
    }
    return texts.labels[pick.id] ?? texts.labels[candidate.tier.name] ?? '';
  }

  /// The personal line the card opens with, from her own log.
  String? _opening() {
    final opening = pick.opening;
    if (opening == null) return null;
    final values = opening.values;
    var template = texts.openings[opening.id];
    if (opening.id == 'P05' && values['min_days'] == values['max_days']) {
      template = texts.openings['P05_same'] ?? template;
    }
    if (template == null) return null;

    String format(String key, Object value) => switch (value) {
          String symptom when key == 'symptom' =>
            (opening.id == 'P02' ? texts.patternPhrase[symptom] : null) ??
                texts.loggedPhrase[symptom] ??
                symptom.toLowerCase(),
          CyclePhase phase => texts.windowPhrase[phase]!,
          DayKey day when key == 'friendly_date' =>
            _friendlyDate(day, values['days_from_today'] as int? ?? 7),
          DayKey day => '${day.day} ${texts.months[day.month - 1]}',
          // Before the double case: on the web every number is a double.
          int days when key == 'relative_to_estimate' => days == 0
              ? texts.ui['onEstimate']!
              : (days < 0
                      ? texts.ui['earlierThanEstimate']!
                      : texts.ui['laterThanEstimate']!)
                  .replaceAll('{n}', '${days.abs()}'),
          double number => number == number.roundToDouble()
              ? number.toInt().toString()
              : number.toStringAsFixed(1),
          _ => '$value',
        };

    var result = template;
    values.forEach(
      (key, value) => result = result.replaceAll('{$key}', format(key, value)),
    );
    // One of something is singular.
    return roCounts(
      result
          .replaceAll(RegExp(r'\b1 days\b'), '1 day')
          .replaceAll(RegExp(r'\b1 hours\b'), '1 hour'),
    );
  }

  String _friendlyDate(DayKey day, int daysFromToday) =>
      switch (daysFromToday) {
        0 => texts.ui['today']!,
        1 => texts.ui['tomorrow']!,
        _ => texts.ui['onDay']!
            .replaceAll('{day}', texts.weekdays[day.weekdayMondayFirst - 1]),
      };

  /// Fills in the cards built from her own log.
  String _fill(String body) {
    final candidate = pick.candidate;
    final pattern = candidate.pattern;
    final lengths = candidate.cycleLengths;
    final high = candidate.energyHigh;
    final low = candidate.energyLow;
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
    return roCounts(result);
  }

  static IconData _icon(InsightTier tier) => switch (tier) {
        InsightTier.safety => Icons.health_and_safety_outlined,
        InsightTier.logged => Icons.edit_note,
        InsightTier.history => Icons.insights,
        InsightTier.education => Icons.menu_book_outlined,
      };
}
