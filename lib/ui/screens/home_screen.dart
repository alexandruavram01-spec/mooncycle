import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/cycle_engine.dart';
import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/profile.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/chat_head.dart';
import '../widgets/cycle_wheel.dart';
import '../widgets/her_insight_card.dart';
import '../widgets/log_sheet.dart';
import '../widgets/moon_face.dart';
import '../widgets/partner_stickers.dart';
import '../widgets/wordmark.dart';
import 'get_help_screen.dart';
import '../../l10n/ui.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(logsProvider);
    final status = ref.watch(cycleStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(size: 26),
        actions: [
          IconButton(
            tooltip: ref.watch(herInsightTextsProvider).ui['openHelp'],
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GetHelpScreen()),
            ),
          ),
        ],
      ),
      // The AI chat bubble floats over Today while the chat is on.
      body: Stack(
        children: [
          Positioned.fill(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(message: '$e'),
              data: (_) {
                if (status == null || !status.hasData) {
                  return const _EmptyState();
                }
                return _HomeBody(status: status);
              },
            ),
          ),
          const Positioned.fill(child: ChatHead()),
        ],
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.status});

  final CycleStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = status.today;
    final todayLog = ref.watch(logByDayProvider(today));
    final phaseColor = MoonColors.forPhase(status.phase);
    final showFertile = ref.watch(showFertileDaysProvider);
    final sharing = ref.watch(settingsProvider).value?.sharing;
    final sharingOn = sharing?.enabled ?? false;
    final requestsOn = sharing?.allowRequests ?? false;
    final conceiving = ref.watch(profileProvider).goal == TrackingGoal.conceive;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(
          child: CycleWheel(
            status: status,
            showFertileWindow: showFertile,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoonFace(phase: status.phase, size: 44),
                const SizedBox(height: 6),
                Text(
                  trf('Day {n}', {'n': status.dayOfCycle}),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(status.phase.label),
                  style:
                      theme.textTheme.titleMedium?.copyWith(color: phaseColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _WheelLegend(showFertile: showFertile),
        // The order testers asked for (30 Oct 2026): her phase first, then
        // when her period is due, then today's card.
        const SizedBox(height: 24),
        _PhaseExplainerCard(status: status, showFertile: showFertile),
        const SizedBox(height: 12),
        _NextPeriodCard(status: status),
        if (showFertile && conceiving) ...[
          const SizedBox(height: 12),
          _FertileDaysCard(status: status),
        ],
        const HerInsightsSection(),
        const SizedBox(height: 12),
        _QuickFlowCard(today: today, current: todayLog?.flow),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => showLogSheet(context, ref, today),
          icon: const Icon(Icons.edit_outlined),
          label: Text(
            todayLog == null ? tr('Log how today feels') : tr('Edit today'),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
        if (todayLog != null && todayLog.symptoms.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                todayLog.symptoms.map((s) => Chip(label: Text(tr(s)))).toList(),
          ),
        ],
        // The partner part sits below her own cards: the tip he got today
        // (to rate), his offers to her and her nudges to him.
        if (sharingOn) ...[
          const SizedBox(height: 16),
          const PartnerTipBanner(),
          const PartnerOfferCard(),
          if (requestsOn) const PartnerNudgeCard(),
        ],
        const SizedBox(height: 24),
        const _MedicalDisclaimer(),
      ],
    );
  }
}

/// Says what the ring's colours, fading and markers mean.
class _WheelLegend extends StatelessWidget {
  const _WheelLegend({required this.showFertile});

  final bool showFertile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium;

    Widget item(Color color, String label, {bool line = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: line ? 16 : 10,
              height: line ? 3 : 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 5),
            Text(label, style: style),
          ],
        );

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final phase in CyclePhase.values)
              item(MoonColors.forPhase(phase), tr(phase.label)),
            if (showFertile)
              item(MoonColors.ovulatory, tr('Fertile days'), line: true),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tr('Solid segments are days so far, faded ones are still to come. '
              'The small moon is today.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _NextPeriodCard extends StatelessWidget {
  const _NextPeriodCard({required this.status});

  final CycleStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = status.daysUntilNextPeriod;
    final next = status.predictedNextStart;
    final formatter = DateFormat('EEEE d MMMM');

    final String headline;
    if (days == null || next == null) {
      headline = tr('Not enough data yet');
    } else if (status.isLate) {
      headline = trCount(-days, 'Period is {n} day late', 'Period is {n} days late');
    } else if (days == 0) {
      headline = tr('Period expected today');
    } else {
      headline = trCount(days, 'Period in {n} day', 'Period in {n} days');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(headline, style: theme.textTheme.titleMedium),
                ),
                _ConfidenceChip(confidence: status.confidence),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 6),
              Text(
                formatter.format(next.toDateTime()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(
                  label: tr('Cycle'),
                  value: '${status.typicalCycleLength}d',
                ),
                _Stat(
                  label: tr('Period'),
                  value: '${status.typicalPeriodLength}d',
                ),
                // Variation needs two full cycles to mean anything.
                _Stat(
                  label: tr('Variation'),
                  value: status.completedCycles < 2
                      ? '—'
                      : '±${status.cycleLengthVariation.toStringAsFixed(1)}d',
                ),
                _Stat(
                  label: tr('Cycles'),
                  value: status.completedCycles == 0
                      ? '—'
                      : '${status.completedCycles}',
                ),
              ],
            ),
            if (status.completedCycles == 0) ...[
              const SizedBox(height: 10),
              Text(
                tr('Estimated from your quiz answers until you have logged a '
                    'full cycle.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final PredictionConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      PredictionConfidence.none => ('First estimate', Colors.grey),
      PredictionConfidence.low => ('Low confidence', Colors.orange),
      PredictionConfidence.medium => ('Fair confidence', Colors.amber),
      PredictionConfidence.high => ('High confidence', Colors.green),
    };
    return Tooltip(
      message: tr('Based on how many cycles you have logged and how much their '
          'length varies.'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tr(label),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color.withValues(alpha: 0.95)),
        ),
      ),
    );
  }
}

/// Shown only when she is trying to conceive: the dates the rest of the app
/// keeps in the background move to the front.
class _FertileDaysCard extends StatelessWidget {
  const _FertileDaysCard({required this.status});

  final CycleStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = status.fertileWindowStart;
    final end = status.fertileWindowEnd;
    if (start == null || end == null) return const SizedBox.shrink();

    final formatter = DateFormat('d MMMM');
    final untilStart = start.differenceInDays(status.today);

    final String headline;
    if (status.isInFertileWindow) {
      headline = tr('You are in your estimated fertile days');
    } else if (untilStart > 0) {
      headline = trCount(untilStart, 'Fertile days start in {n} day',
          'Fertile days start in {n} days');
    } else {
      headline = tr('Fertile days have passed for this cycle');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.eco_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(headline, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              trf('{start} to {end}, estimated from your cycle history.', {
                'start': formatter.format(start.toDateTime()),
                'end': formatter.format(end.toDateTime()),
              }),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseExplainerCard extends StatelessWidget {
  const _PhaseExplainerCard({required this.status, required this.showFertile});

  final CycleStatus status;
  final bool showFertile;

  static const Map<CyclePhase, String> _hormones = {
    CyclePhase.menstrual:
        'Oestrogen and progesterone are at their lowest. Low energy and cramps '
            'are common; prostaglandins drive the cramping.',
    CyclePhase.follicular:
        'Oestrogen is rising as a follicle matures. Energy, mood and focus '
            'usually climb with it.',
    CyclePhase.ovulatory:
        'A surge of LH releases the egg. Oestrogen peaks — often the highest '
            'energy days of the cycle.',
    CyclePhase.luteal:
        'Progesterone rises then falls if there is no pregnancy. That drop is '
            'what drives PMS symptoms in the final days.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = MoonColors.forPhase(status.phase);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  tr('${status.phase.label} phase'),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(_hormones[status.phase]!),
              style: theme.textTheme.bodyMedium,
            ),
            if (showFertile && status.isInFertileWindow) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.eco_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('You are in your estimated fertile window.'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickFlowCard extends ConsumerWidget {
  const _QuickFlowCard({required this.today, required this.current});

  final DayKey today;
  final FlowIntensity? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr("Today's flow"), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: FlowIntensity.values.map((f) {
                final selected = (current ?? FlowIntensity.none) == f;
                return ChoiceChip(
                  label: Text(tr(f.label)),
                  selected: selected,
                  onSelected: (_) async {
                    final existing = ref.read(logByDayProvider(today)) ??
                        DayLog(date: today);
                    await ref
                        .read(logsProvider.notifier)
                        .save(existing.copyWith(flow: f));
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const MoonFace(phase: CyclePhase.follicular, size: 72),
            const SizedBox(height: 20),
            Text(tr('Let us find your rhythm'),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              tr('Mark the first day of your last period. Predictions get sharper '
                  'with every cycle you log.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                  helpText: tr('First day of your last period'),
                );
                if (picked == null) return;
                final day = DayKey.fromDateTime(picked);
                await ref.read(logsProvider.notifier).save(
                      DayLog(
                        date: day,
                        flow: FlowIntensity.medium,
                        isPeriodStartOverride: true,
                      ),
                    );
              },
              child: Text(tr('Set my last period')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicalDisclaimer extends StatelessWidget {
  const _MedicalDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      tr('Predictions are estimates based on your own history. They are not '
          'contraception and not medical advice.'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('Something went wrong.')}\n\n$message',
              textAlign: TextAlign.center),
        ),
      );
}
