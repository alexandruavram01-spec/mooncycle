import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_language.dart';
import '../../state/providers.dart';
import '../widgets/wordmark.dart';
import '../../l10n/ui.dart';

/// Choose the app's language. Shown by the gate in `main.dart` before
/// sign-in on a new device, and from Settings (or his menu) afterwards with
/// [pushed] set.
///
/// Each person picks their own: she can read the app in UK English while her
/// partner reads it in International English.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key, this.pushed = false});

  /// Opened from Settings: has a back button and closes once saved.
  final bool pushed;

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  /// Nothing is picked for them: empty until they choose, or the language
  /// they chose before when opened from Settings.
  late AppLanguage? _selected = ref.read(languageProvider).valueOrNull;
  bool _saving = false;

  Future<void> _save(AppLanguage language) async {
    setState(() => _saving = true);
    try {
      await ref.read(languageProvider.notifier).choose(language);
      if (mounted && widget.pushed) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Scaffold(
      appBar: widget.pushed ? AppBar(title: Text(tr('Language'))) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                if (!widget.pushed) ...[
                  const Center(child: LogoMark(size: 120)),
                  const SizedBox(height: 8),
                  const Center(child: Wordmark(size: 32)),
                  const SizedBox(height: 20),
                  Text(
                    tr('Choose your language'),
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
                for (final language in AppLanguage.values)
                  Card(
                    color: _selected == language
                        ? scheme.primaryContainer
                        : null,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Icon(
                        _selected == language
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: scheme.primary,
                      ),
                      title: Text(language.label),
                      subtitle: Text(language.hint),
                      onTap: _saving
                          ? null
                          : () => setState(() => _selected = language),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  tr('It sets the language of the app and of partner tips and '
                  'messages. Your partner chooses their own, and you can '
                  'change yours any time in Settings.'),
                  style: muted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: switch (_selected) {
                    final language? when !_saving => () => _save(language),
                    _ => null,
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(
                    _saving
                        ? tr('Saving…')
                        : widget.pushed
                            ? tr('Save')
                            : tr('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
