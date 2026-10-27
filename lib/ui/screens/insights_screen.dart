import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/insights.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../../l10n/ui.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final patterns = ref.watch(patternsProvider);
    final phases = ref.watch(phaseAveragesProvider);
    final history = ref.watch(cycleLengthHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Patterns'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (history.length < 2)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  trf(
                    'Patterns need at least {n} complete cycles before they '
                    'mean anything. Keep logging — this page fills in on its '
                    'own.',
                    {'n': InsightsEngine.minCyclesForPattern},
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          if (history.length >= 2) ...[
            Text(tr('Cycle length'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(height: 180, child: _CycleLengthChart(history: history)),
            const SizedBox(height: 28),
          ],
          Text(tr('How each phase tends to feel'),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...phases.where((p) => p.sampleDays > 0).map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: MoonColors.forPhase(p.phase),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(tr(p.phase.label),
                                  style: theme.textTheme.titleSmall),
                              const Spacer(),
                              if (p.averageEnergy != null)
                                Text(
                                  trf('Energy {value}/5', {
                                    'value':
                                        p.averageEnergy!.toStringAsFixed(1),
                                  }),
                                  style: theme.textTheme.labelMedium,
                                ),
                            ],
                          ),
                          if (p.topSymptoms.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: p.topSymptoms
                                  .map((s) => Chip(
                                        label: Text(tr(s)),
                                        visualDensity: VisualDensity.compact,
                                      ))
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            trCount(p.sampleDays, '{n} day logged',
                                '{n} days logged'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          if (patterns.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(tr('What repeats'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...patterns.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 40,
                  child: Center(
                    child: Text('${(p.strength * 100).round()}%',
                        style: theme.textTheme.labelLarge),
                  ),
                ),
                title: Text(trf('{symptom} in your {phase} phase', {
                  'symptom': tr(p.symptom),
                  'phase': tr(p.phase.label).toLowerCase(),
                })),
                subtitle: Text(trf(
                  'Logged in {hits} of {cycles} recent cycles.',
                  {'hits': p.hits, 'cycles': p.cycles},
                )),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CycleLengthChart extends StatelessWidget {
  const _CycleLengthChart({required this.history});

  final List<int> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), history[i].toDouble()),
    ];
    final minY = (history.reduce((a, b) => a < b ? a : b) - 3).toDouble();
    final maxY = (history.reduce((a, b) => a > b ? a : b) + 3).toDouble();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt() + 1}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 5,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            barWidth: 3,
            color: MoonColors.seed,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: MoonColors.seed.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
