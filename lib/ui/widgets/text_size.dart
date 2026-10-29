import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/ui.dart';

/// How big the app's text is, on top of the phone's own text size. Kept on
/// this phone only, for whoever uses it.
enum TextSize {
  normal(1.0, 'Normal'),
  large(1.15, 'Large'),
  larger(1.3, 'Larger'),
  largest(1.5, 'Largest');

  const TextSize(this.factor, this.label);

  final double factor;
  final String label;
}

/// Everyone's text is this much bigger than Flutter's default: the app read
/// as small. [TextSize] multiplies it.
const baseTextScale = 1.08;

class TextSizeNotifier extends AsyncNotifier<TextSize> {
  static const _key = 'mooncycle.textSize';

  @override
  Future<TextSize> build() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    return TextSize.values.firstWhere(
      (size) => size.name == name,
      orElse: () => TextSize.normal,
    );
  }

  Future<void> choose(TextSize size) async {
    state = AsyncData(size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, size.name);
  }
}

final textSizeProvider =
    AsyncNotifierProvider<TextSizeNotifier, TextSize>(TextSizeNotifier.new);

/// The text scale for the whole app: the phone's setting, the app's base and
/// her or his choice, capped so screens stay usable.
TextScaler appTextScaler(TextScaler phone, TextSize size) {
  final fromPhone = phone.scale(100) / 100;
  return TextScaler.linear(
    (fromPhone * baseTextScale * size.factor).clamp(1.0, 2.4),
  );
}

/// Settings → Text size: four sizes, with a sample that changes as you pick.
Future<void> showTextSizeSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _TextSizeSheet(),
    );

class _TextSizeSheet extends ConsumerWidget {
  const _TextSizeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(textSizeProvider).value ?? TextSize.normal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Text size'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              tr("Makes all text in MoonCycle bigger. Your phone's own text "
                  'size setting still applies too.'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            RadioGroup<TextSize>(
              groupValue: current,
              onChanged: (size) {
                if (size != null) ref.read(textSizeProvider.notifier).choose(size);
              },
              child: Column(
                children: [
                  for (final size in TextSize.values)
                    RadioListTile<TextSize>(
                      contentPadding: EdgeInsets.zero,
                      value: size,
                      title: Text(tr(size.label)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
