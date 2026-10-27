import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/partner_tips.dart';
import '../../domain/profile.dart';
import '../../l10n/partner_messages.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'moon_face.dart';
import '../../l10n/ui.dart';

/// The card a partner sees, always in the Night theme.
///
/// It is framed as a forecast rather than a report: where she is in her
/// cycle, one thing to do today in the tone he chose, and what is coming
/// next. The longer background sits behind "More about this phase". Every
/// sentence comes from his own language file; her phone sends only the
/// phase and numbers.
class PartnerPreview extends StatelessWidget {
  const PartnerPreview({
    super.key,
    required this.snapshot,
    this.name = '',
    this.tone = PartnerTone.light,
  });

  final PartnerSnapshot snapshot;

  /// What the partner calls her. Empty falls back to "she" and "her".
  final String name;
  final PartnerTone tone;

  @override
  Widget build(BuildContext context) => Theme(
        data: nightTheme,
        child: _ForecastCard(snapshot: snapshot, name: name, tone: tone),
      );
}

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard({
    required this.snapshot,
    required this.name,
    required this.tone,
  });

  final PartnerSnapshot snapshot;
  final String name;
  final PartnerTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final messages = ref.watch(partnerMessagesProvider);
    final pulled =
        ref.watch(pulledTipsProvider).valueOrNull ?? const <String>{};
    final phase = snapshot.phase;
    final card = phase == null ? null : messages.cards[phase];
    final nextPhase = snapshot.nextPhase;
    final daysUntilNextPhase = snapshot.daysUntilNextPhase;
    final energy = snapshot.energy;
    // His chosen tone applies only on days she allows jokes; see
    // jokesAllowed in lib/domain/partner.dart.
    final tone = snapshot.jokes ? this.tone : PartnerTone.straight;
    final move =
        PartnerTips.pickMove(messages, phase, tone, DayKey.today(), pulled);
    final note = card?.note;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (phase != null) ...[
                  MoonFace(phase: phase, size: 56),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr("Tonight's sky"),
                        style:
                            theme.textTheme.labelMedium?.copyWith(color: muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card?.summary ?? tr('Cycle phase not shared'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (card != null) ...[
                        const SizedBox(height: 2),
                        Text(card.headline, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (phase != null) ...[
              const SizedBox(height: 16),
              _PhaseMoons(current: phase, messages: messages),
            ],
            if (snapshot.daysUntilNextPeriod != -999) ...[
              const SizedBox(height: 14),
              Text(
                _countdown(messages, snapshot.daysUntilNextPeriod),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (move != null) ...[
              const SizedBox(height: 18),
              Text(
                tr("Today's move"),
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: 4),
              Text(move.text, style: theme.textTheme.titleMedium),
              _TipRating(key: ValueKey(move.id), code: move.id),
            ],
            if (nextPhase != null && daysUntilNextPhase != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      PartnerTips.headsUp(
                        messages,
                        nextPhase,
                        daysUntilNextPhase,
                        tone,
                      ),
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ],
            if (snapshot.sharedSymptoms.isNotEmpty || energy != null) ...[
              const SizedBox(height: 18),
              Text(
                name.isEmpty
                    ? tr('She logged today')
                    : trf('{name} logged today', {'name': name}),
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (energy != null)
                    Chip(
                      label: Text(trf('Energy {n} of 5', {'n': energy})),
                      visualDensity: VisualDensity.compact,
                    ),
                  ...snapshot.sharedSymptoms.map(
                    (s) => Chip(
                      label: Text(tr(s)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
            if (card != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                expandedAlignment: Alignment.centerLeft,
                // No divider lines above and below when open.
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  tr('More about this phase'),
                  style: theme.textTheme.labelLarge,
                ),
                children: [
                  Text(
                    name.isEmpty
                        ? tr('What she may be feeling')
                        : trf('What {name} may be feeling', {'name': name}),
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  ...card.mayFeel.map(_bullet),
                  const SizedBox(height: 10),
                  Text(tr('How to help'), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  ...card.howToHelp.map(_bullet),
                  if (note != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ] else
              const SizedBox(height: 14),
            Text(
              tr('A forecast from typical patterns, not a readout of how she '
              'actually feels. Ask her.'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  /// A prediction only. Whether her period has actually started is the
  /// headline's job, and that comes from what she logged.
  static String _countdown(PartnerMessages messages, int days) {
    if (days <= 0) return messages.periodExpectedNow;
    final line =
        messages.periodExpectedIn.replaceAll('{days}', messages.days(days));
    return days <= 2 ? '$line ${messages.periodSoonAsk}' : line;
  }

  static Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// Lets him rate today's tip. "Not okay" takes the line down for everyone
/// until an editor looks at it.
class _TipRating extends ConsumerStatefulWidget {
  const _TipRating({super.key, required this.code});

  final String code;

  @override
  ConsumerState<_TipRating> createState() => _TipRatingState();
}

class _TipRatingState extends ConsumerState<_TipRating> {
  String? _given;

  Future<void> _rate(String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _given = kind);
    try {
      await ref.read(tipLibraryServiceProvider).rate(widget.code, kind);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (kind) {
            'not_okay' => tr('Removed for everyone. Thanks for flagging it.'),
            'not_funny' => tr('Noted. Fewer like that.'),
            _ => tr('Glad that one landed.'),
          }),
        ),
      );
      if (kind == 'not_okay' && mounted) ref.invalidate(pulledTipsProvider);
    } catch (e) {
      if (mounted) setState(() => _given = null);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget option(IconData icon, String label, String kind) {
      final chosen = _given == kind;
      return TextButton.icon(
        onPressed: chosen ? null : () => _rate(kind),
        icon: Icon(icon, size: 16),
        label: Text(tr(label)),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          disabledForegroundColor: theme.colorScheme.primary,
        ),
      );
    }

    return Wrap(
      spacing: 4,
      children: [
        option(Icons.thumb_up_outlined, 'Nice', 'like'),
        option(Icons.sentiment_neutral, 'Not funny', 'not_funny'),
        option(Icons.flag_outlined, 'Not okay', 'not_okay'),
      ],
    );
  }
}

/// The four phases as moons, in order, with the current one lit.
class _PhaseMoons extends StatelessWidget {
  const _PhaseMoons({required this.current, required this.messages});

  final CyclePhase current;
  final PartnerMessages messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (final phase in CyclePhase.values)
          Expanded(
            child: Column(
              children: [
                MoonPhaseIcon(phase: phase, highlighted: phase == current),
                const SizedBox(height: 4),
                Text(
                  messages.cards[phase]!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: phase == current ? FontWeight.w700 : null,
                    color: phase == current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
