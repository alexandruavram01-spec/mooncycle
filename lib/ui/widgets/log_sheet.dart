import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

Future<void> showLogSheet(BuildContext context, WidgetRef ref, DayKey day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LogSheet(day: day),
  );
}

class LogSheet extends ConsumerStatefulWidget {
  const LogSheet({super.key, required this.day});

  final DayKey day;

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet> {
  late FlowIntensity _flow;
  late Set<String> _symptoms;
  int? _energy;
  bool? _periodStartOverride;
  late TextEditingController _notes;
  late TextEditingController _sleep;
  double? _oldTemperature;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(logByDayProvider(widget.day));
    _flow = existing?.flow ?? FlowIntensity.none;
    _symptoms = {...?existing?.symptoms};
    _energy = existing?.energy;
    _periodStartOverride = existing?.isPeriodStartOverride;
    _notes = TextEditingController(text: existing?.notes ?? '');
    _sleep = TextEditingController(
        text: existing?.sleepHours?.toStringAsFixed(1) ?? '');
    // Temperature is no longer asked for; a value saved before is kept.
    _oldTemperature = existing?.basalTemperature;
  }

  @override
  void dispose() {
    _notes.dispose();
    _sleep.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final log = DayLog(
      date: widget.day,
      flow: _flow,
      symptoms: _symptoms,
      energy: _energy,
      sleepHours: double.tryParse(_sleep.text.replaceAll(',', '.')),
      basalTemperature: _oldTemperature,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isPeriodStartOverride: _periodStartOverride,
    );
    try {
      await ref.read(logsProvider.notifier).save(log);
    } catch (e) {
      // Never fail silently: a Save that does nothing looks like a lost day.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this day: $e')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _symptomChip(String symptom) => FilterChip(
        label: Text(symptom),
        selected: _symptoms.contains(symptom),
        onSelected: (on) => setState(() {
          if (on) {
            // Desire is one of low, usual or high.
            if (SymptomCatalog.desire.contains(symptom)) {
              _symptoms.removeAll(SymptomCatalog.desire);
            }
            _symptoms.add(symptom);
          } else {
            _symptoms.remove(symptom);
          }
        }),
      );

  /// What people see for a group, and a hint under it. The stored names
  /// ("Fluid", "Sex") stay as they are, so past days and the cards still
  /// match.
  static const _groupLabels = {
    'Fluid': 'Fluid (fertile phase)',
    'Sex': 'Sex and desire',
  };
  static const _groupHints = {
    'Fluid': 'The fluid you may notice between periods. Around your fertile '
        'days it often becomes clear and stretchy, like raw egg white.',
    'Sex': 'Desire on this day, and sex if you had it. Leave desire '
        'unticked if you are not sure.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Her quiz answers decide what comes first; nothing is ever hidden.
    final profile = ref.watch(profileProvider);
    final leading = <String>[
      if (profile.trackedSigns.contains('fluid')) 'Fluid',
      if (profile.focus.contains('pain')) 'Pain',
      if (profile.focus.contains('mood')) 'Mood',
    ];
    final groupOrder = [
      ...leading,
      ...SymptomCatalog.groups.keys.where((g) => !leading.contains(g)),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        // The date and Save stay pinned at the top, so filling in many days
        // never means scrolling down to save each one.
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE d MMMM')
                          .format(widget.day.toDateTime()),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  // The iPhone's number keyboard has no key to close it.
                  if (bottomInset > 0)
                    TextButton(
                      onPressed: () => FocusScope.of(context).unfocus(),
                      child: const Text('Done'),
                    ),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Everything here is about this day, whether or not you are '
                  'on your period.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              // A tap outside a box closes the keyboard too.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusScope.of(context).unfocus(),
                child: _fields(context, controller, groupOrder),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fields(
    BuildContext context,
    ScrollController controller,
    List<String> groupOrder,
  ) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);
    return ListView(
          controller: controller,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _SectionLabel('Flow'),
            Wrap(
              spacing: 8,
              children: FlowIntensity.values
                  .map(
                    (f) => ChoiceChip(
                      label: Text(f.label),
                      selected: _flow == f,
                      onSelected: (_) => setState(() => _flow = f),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Energy'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final level = i + 1;
                final selected = _energy == level;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: OutlinedButton(
                      onPressed: () => setState(
                        () => _energy = selected ? null : level,
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: selected
                            ? theme.colorScheme.primaryContainer
                            : null,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('$level'),
                    ),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '1 = drained, 5 = energised',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (profile.usualSymptoms.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _SectionLabel('Your usual'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: profile.usualSymptoms.map(_symptomChip).toList(),
              ),
            ],
            for (final group in groupOrder) ...[
              const SizedBox(height: 14),
              _SectionLabel(_groupLabels[group] ?? group),
              if (_groupHints[group] case final hint?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    SymptomCatalog.groups[group]!.map(_symptomChip).toList(),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _sleep,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Sleep last night (hours)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _periodStartOverride == true,
              onChanged: (on) => setState(
                () => _periodStartOverride = on ? true : null,
              ),
              title: const Text('This is the first day of my period'),
              subtitle: const Text(
                'Use this if the app grouped your days incorrectly.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Save'),
            ),
          ],
        );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}
