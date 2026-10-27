import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/consent_boxes.dart';
import '../widgets/wordmark.dart';
import '../../l10n/ui.dart';

/// Shown once to accounts that have not agreed to the current terms: those
/// made with Google from the sign-in screen, those made before consent was
/// recorded, and everyone after the terms change.
class LegalConsentScreen extends ConsumerStatefulWidget {
  const LegalConsentScreen({super.key});

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  bool _terms = false;
  bool _health = false;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(legalConsentProvider.notifier).accept();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${tr('Could not save your answer. Check your connection '
              'and try again.')} ($e)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Center(child: LogoMark(size: 100)),
                const SizedBox(height: 8),
                const Center(child: Wordmark(size: 32)),
                const SizedBox(height: 16),
                Text(
                  tr('Before you continue'),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Please read our terms and privacy policy, and tick both '
                  'boxes to use MoonCycle.'),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ConsentBoxes(
                  terms: _terms,
                  health: _health,
                  enabled: !_busy,
                  onTerms: (v) => setState(() => _terms = v),
                  onHealth: (v) => setState(() => _health = v),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      _terms && _health && !_busy ? _continue : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(_busy ? tr('One moment…') : tr('Continue')),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref.read(sessionProvider.notifier).signOut(),
                  child: Text(tr('Sign out')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
