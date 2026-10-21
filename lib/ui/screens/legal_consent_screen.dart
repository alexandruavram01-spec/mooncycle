import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/consent_boxes.dart';
import '../widgets/wordmark.dart';

/// Shown once to accounts that have not agreed to the current terms: those
/// made before consent was recorded, and everyone after the terms change.
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
          _error = 'Could not save your answer. Check your connection and '
              'try again. ($e)';
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
                const Center(child: Wordmark(size: 32)),
                const SizedBox(height: 16),
                Text(
                  'Before you continue',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'We have published our terms and privacy policy. Please read '
                  'them and tick both boxes to keep using MoonCycle.',
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
                  child: Text(_busy ? 'One moment…' : 'Continue'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref.read(sessionProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
