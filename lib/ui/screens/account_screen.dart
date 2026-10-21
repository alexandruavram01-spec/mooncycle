import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../widgets/consent_boxes.dart';
import '../widgets/moon_face.dart';
import '../widgets/wordmark.dart';
import 'language_screen.dart';

/// Create an account or sign in. Shown by the gate in `main.dart` whenever
/// nobody is signed in; a successful submit replaces it with the app.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  static const _minPasswordLength = 8;

  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = true;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// The two consent boxes on sign-up. Never ticked in advance.
  bool _terms = false;
  bool _health = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    // Only sign-up insists on an email address: the server also has a few
    // test accounts with plain names (see BEFORE_LAUNCH.md).
    String? problem;
    if (email.isEmpty || (_creating && !email.contains('@'))) {
      problem = 'Enter your email address.';
    } else if (_creating && password.length < _minPasswordLength) {
      problem = 'Use a password of at least $_minPasswordLength characters.';
    } else if (password.isEmpty) {
      problem = 'Enter your password.';
    } else if (_creating && !(_terms && _health)) {
      problem = 'Please tick both boxes to create your account.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_creating) {
        await session.signUp(email, password);
      } else {
        await session.signIn(email, password);
      }
      // Success replaces this screen, so there is nothing left to update.
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Center(
                  child: MoonFace(phase: CyclePhase.ovulatory, size: 72),
                ),
                const SizedBox(height: 12),
                const Center(child: Wordmark(size: 32)),
                const SizedBox(height: 16),
                Text(
                  _creating ? 'Create your account' : 'Welcome back',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: [
                    _creating
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                Text(
                  _creating
                      ? 'Choose a password you will remember. It cannot be '
                          'reset yet.'
                      : 'Password reset is not available yet. If you have '
                          'forgotten it, you will need a new account.',
                  style: muted,
                ),
                if (_creating) ...[
                  const SizedBox(height: 12),
                  ConsentBoxes(
                    terms: _terms,
                    health: _health,
                    enabled: !_busy,
                    onTerms: (v) => setState(() => _terms = v),
                    onHealth: (v) => setState(() => _health = v),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      _busy || (_creating && !(_terms && _health))
                          ? null
                          : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(
                    _busy
                        ? 'One moment…'
                        : _creating
                            ? 'Create account'
                            : 'Sign in',
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                          }),
                  child: Text(
                    _creating
                        ? 'I already have an account'
                        : 'Create an account',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Your logs and quiz answers stay on this device. The '
                  'account holds only your email and your partner connection.',
                  style: muted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const LanguageScreen(pushed: true),
                              ),
                            ),
                    icon: const Icon(Icons.language, size: 18),
                    label: Text(
                      ref.watch(languageProvider).valueOrNull?.label ??
                          'Language',
                    ),
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
