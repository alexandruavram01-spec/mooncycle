import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../legal.dart';
import '../../services/apple_account.dart';
import '../../services/google_account.dart';
import '../../state/providers.dart';
import '../widgets/consent_boxes.dart';
import '../widgets/links.dart';
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
  String? _googleError;

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

    String? problem;
    if (email.isEmpty || !email.contains('@')) {
      problem = 'Enter your email address.';
    } else if (_creating && password.length < _minPasswordLength) {
      problem = 'Use a password of at least $_minPasswordLength characters.';
    } else if (_creating && !RegExp('[A-Z]').hasMatch(password)) {
      problem = 'Add at least one capital letter to your password.';
    } else if (_creating && !RegExp(r'[^A-Za-z0-9\s]').hasMatch(password)) {
      problem = 'Add at least one special character to your password, '
          'such as ! # or ?.';
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

  /// Works from both screens. If she already ticked both boxes on the
  /// sign-up screen, a new account records her consent; otherwise the
  /// consent screen comes next, before anything else.
  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _googleError = null;
    });
    try {
      final signedIn = await ref
          .read(sessionProvider.notifier)
          .signInWithGoogle(consent: _creating && _terms && _health);
      // Success replaces this screen.
      if (mounted && !signedIn) {
        setState(() {
          _busy = false;
          _googleError = 'Google sign-in was closed before it finished. '
              'Try again, or use your email and password.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _googleError = '$e';
        });
      }
    }
  }

  /// Sign in with Apple (iPhone), the same way as Google.
  Future<void> _apple() async {
    setState(() {
      _busy = true;
      _error = null;
      _googleError = null;
    });
    try {
      final signedIn = await ref
          .read(sessionProvider.notifier)
          .signInWithApple(consent: _creating && _terms && _health);
      if (mounted && !signedIn) {
        setState(() {
          _busy = false;
          _googleError = 'Sign in with Apple was closed before it finished. '
              'Try again, or use your email and password.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _googleError = '$e';
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
                const Center(child: LogoMark(size: 120)),
                const SizedBox(height: 8),
                const Center(child: Wordmark(size: 32)),
                const SizedBox(height: 16),
                Text(
                  _creating ? 'Create your account' : 'Welcome back',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (GoogleAccount.available || AppleAccount.available) ...[
                  if (AppleAccount.available) ...[
                    _AppleButton(onPressed: _busy ? null : _apple),
                    if (GoogleAccount.available) const SizedBox(height: 12),
                  ],
                  if (GoogleAccount.available)
                    _GoogleButton(onPressed: _busy ? null : _google),
                  if (_googleError case final message?) ...[
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or use your email', style: muted),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
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
                    helperText: _creating
                        ? 'At least $_minPasswordLength characters, with a '
                            'capital letter and a special character'
                        : null,
                    helperMaxLines: 2,
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
                  'account holds only your email and your partner connection '
                  '(and, with Google, an ID for your Google account).',
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
                // Sign-up shows these inside the consent boxes.
                if (!_creating)
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (label, url) in [
                        ('Privacy policy', Legal.privacyUrl),
                        ('Terms of use', Legal.termsUrl),
                        ('Health information', Legal.healthUrl),
                      ])
                        TextButton(
                          onPressed: () => openExternal(
                            context,
                            Uri.parse(url),
                            'Could not open the page.',
                          ),
                          child: Text(label, style: muted),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple's sign-in button: black, the Apple logo and "Continue with Apple",
/// as Apple's design guidelines describe.
class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.apple, size: 22),
      label: const Text('Continue with Apple'),
    );
  }
}

/// Google's sign-in button: white, Google's "G" and "Continue with Google",
/// full width, as its branding guidelines describe.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1F1F),
        side: const BorderSide(color: Color(0xFF747775)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(painter: _GoogleG()),
          ),
          SizedBox(width: 12),
          Text('Continue with Google'),
        ],
      ),
    );
  }
}

/// Google's four-colour "G", drawn so no image file is needed.
class _GoogleG extends CustomPainter {
  const _GoogleG();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );
    Paint arc(int colour) => Paint()
      ..color = Color(colour)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double rad(double degrees) => degrees * 3.141592653589793 / 180;
    // Clockwise from the bar at three o'clock; the gap is at the top right.
    canvas.drawArc(rect, rad(0), rad(50), false, arc(0xFF4285F4));
    canvas.drawArc(rect, rad(50), rad(90), false, arc(0xFF34A853));
    canvas.drawArc(rect, rad(140), rad(75), false, arc(0xFFFBBC05));
    canvas.drawArc(rect, rad(215), rad(100), false, arc(0xFFEA4335));
    canvas.drawRect(
      Rect.fromLTRB(
        size.width / 2,
        size.height / 2 - stroke / 2,
        size.width,
        size.height / 2 + stroke / 2,
      ),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
