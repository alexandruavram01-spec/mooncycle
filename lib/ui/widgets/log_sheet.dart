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
  late TextEditingController _bbt;

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
    _bbt = TextEditingController(
        text: existing?.basalTemperature?.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    _sleep.dispose();
    _bbt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final log = DayLog(
      date: widget.day,
      flow: _flow,
      symptoms: _symptoms,
      energy: _energy,
      sleepHours: double.tryParse(_sleep.text.replaceAll(',', '.')),
      basalTemperature: double.tryParse(_bbt.text.replaceAll(',', '.')),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isPeriodStartOverride: _periodStartOverride,
    );
    await ref.read(logsProvider.notifier).save(log);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _symptomChip(String symptom) => FilterChip(
        label: Text(symptom),
        selected: _symptoms.contains(symptom),
        onSelected: (on) => setState(() {
          if (on) {
            _symptoms.add(symptom);
          } else {
            _symptoms.remove(symptom);
          }
        }),
      );

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
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              DateFormat('EEEE d MMMM').format(widget.day.toDateTime()),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
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
              _SectionLabel(group),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    SymptomCatalog.groups[group]!.map(_symptomChip).toList(),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sleep,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Sleep (hours)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _bbt,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Temperature (°C)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
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
        ),
      ),
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
