import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/cycle_engine.dart';
import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/log_sheet.dart';
import '../../l10n/ui.dart';

/// How a single calendar cell should be rendered.
enum DayMarker { none, logged, predictedPeriod, fertile, ovulation }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// Page 0 is 24 months ago, so users can scroll back through history and
  /// forward into predictions from one controller.
  static const int _monthsBack = 24;
  static const int _monthsForward = 12;

  late final PageController _controller =
      PageController(initialPage: _monthsBack);

  DateTime _monthForPage(int page) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - _monthsBack + page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Swiping does not work with a mouse in the browser, so months also turn
  /// with the arrows beside the month name.
  void _turn(int months) {
    final page = (_controller.page ?? _monthsBack).round() + months;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider).value ?? const <DayLog>[];
    final status = ref.watch(cycleStatusProvider);
    final engine = ref.watch(cycleEngineProvider);
    final showFertile = ref.watch(showFertileDaysProvider);
    final cycles = engine.deriveCycles(logs);
    final futureStarts = engine.predictedStarts(
      cycles,
      DayKey.today(),
      count: _monthsForward,
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Calendar'))),
      body: Column(
        children: [
          _Legend(showFertile: showFertile),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _monthsBack + _monthsForward + 1,
              itemBuilder: (context, page) {
                final month = _monthForPage(page);
                return _MonthView(
                  month: month,
                  logs: logs,
                  status: status,
                  showFertile: showFertile,
                  futurePeriodStarts: futureStarts,
                  onTapDay: (day) => showLogSheet(context, ref, day),
                  onPrevious: page > 0 ? () => _turn(-1) : null,
                  onNext: page < _monthsBack + _monthsForward
                      ? () => _turn(1)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.logs,
    required this.status,
    required this.showFertile,
    required this.futurePeriodStarts,
    required this.onTapDay,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final List<DayLog> logs;
  final CycleStatus? status;
  final bool showFertile;
  final List<DayKey> futurePeriodStarts;
  final void Function(DayKey) onTapDay;

  /// Null at either end of the range.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first grid.
    final leadingBlanks = first.weekday - 1;
    final logsByDate = {for (final l in logs) l.date: l};
    final today = DayKey.today();

    // A list rather than a fixed column, so a short window can scroll to the
    // last week instead of cutting it off.
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Previous month'),
                icon: const Icon(Icons.chevron_left),
                onPressed: onPrevious,
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: tr('Next month'),
                icon: const Icon(Icons.chevron_right),
                onPressed: onNext,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(d, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          physics: const NeverScrollableScrollPhysics(),
          // Fixed-height rows: square cells grew huge on a wide screen.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 52,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final dayNumber = index - leadingBlanks + 1;
            final day = DayKey(month.year, month.month, dayNumber);
            return _DayCell(
              day: day,
              log: logsByDate[day],
              marker: _markerFor(day),
              isToday: day == today,
              onTap: () => onTapDay(day),
            );
          },
        ),
      ],
    );
  }

  DayMarker _markerFor(DayKey day) {
    final s = status;
    if (s == null) return DayMarker.none;

    if (showFertile &&
        s.predictedOvulation != null &&
        day == s.predictedOvulation) {
      return DayMarker.ovulation;
    }
    if (showFertile &&
        s.fertileWindowStart != null &&
        s.fertileWindowEnd != null &&
        !day.isBefore(s.fertileWindowStart!) &&
        !day.isAfter(s.fertileWindowEnd!)) {
      return DayMarker.fertile;
    }
    for (final start in futurePeriodStarts) {
      final offset = day.differenceInDays(start);
      if (offset >= 0 && offset < s.typicalPeriodLength) {
        return DayMarker.predictedPeriod;
      }
    }
    return DayMarker.none;
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.log,
    required this.marker,
    required this.isToday,
    required this.onTap,
  });

  final DayKey day;
  final DayLog? log;
  final DayMarker marker;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bleeding = log?.flow.isBleeding ?? false;

    Color? fill;
    Border? border;

    if (bleeding) {
      fill = MoonColors.menstrual.withValues(
        alpha: switch (log!.flow) {
          FlowIntensity.spotting => 0.25,
          FlowIntensity.light => 0.45,
          FlowIntensity.medium => 0.7,
          FlowIntensity.heavy => 0.95,
          FlowIntensity.none => 0.0,
        },
      );
    } else {
      switch (marker) {
        case DayMarker.predictedPeriod:
          border = Border.all(color: MoonColors.menstrual, width: 1.4);
        case DayMarker.ovulation:
          fill = MoonColors.ovulatory.withValues(alpha: 0.85);
        case DayMarker.fertile:
          fill = MoonColors.ovulatory.withValues(alpha: 0.25);
        case DayMarker.logged:
        case DayMarker.none:
          break;
      }
    }

    final hasOtherData =
        log != null && !bleeding && (log!.symptoms.isNotEmpty || log!.energy != null);

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: fill,
            border: border ??
                (isToday
                    ? Border.all(color: theme.colorScheme.onSurface, width: 1.6)
                    : null),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: (fill != null && fill.a > 0.6)
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (hasOtherData)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showFertile});

  final bool showFertile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          _LegendDot(color: MoonColors.menstrual, label: tr('Period')),
          _LegendDot(
            color: MoonColors.menstrual,
            label: tr('Predicted'),
            outlined: true,
          ),
          if (showFertile)
            _LegendDot(color: MoonColors.ovulatory, label: tr('Fertile')),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: outlined ? null : color,
            border: outlined ? Border.all(color: color, width: 1.5) : null,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
