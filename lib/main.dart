import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/profile.dart';
import 'state/providers.dart';
import 'ui/screens/account_screen.dart';
import 'ui/screens/editor_home_screen.dart';
import 'ui/screens/language_screen.dart';
import 'ui/screens/legal_consent_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/partner_view_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Own the container explicitly so notification channels can be created
  // before the first frame.
  final container = ProviderContainer();

  // Anything that fails here must not stop the app from rendering — a crash
  // before runApp produces a blank window with no on-screen clue why.
  try {
    await container.read(notificationServiceProvider).init();
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'mooncycle',
        context: ErrorDescription('initialising notifications'),
      ),
    );
  }

  // Idle until sharing is switched on and a pairing code exists.
  try {
    container
      ..read(partnerSyncProvider)
      ..read(partnerTipReminderProvider);
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'mooncycle',
        context: ErrorDescription('starting partner sync'),
      ),
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MoonCycleApp(),
    ),
  );
}

class MoonCycleApp extends ConsumerWidget {
  const MoonCycleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The look follows the role, not the phone's light or dark setting: Dawn
    // for someone tracking her cycle, Night for a partner.
    final partner = ref.watch(profileProvider).role == AppRole.partner;

    return MaterialApp(
      title: 'MoonCycle',
      debugShowCheckedModeBanner: false,
      theme: partner ? nightTheme : dawnTheme,
      // On a wide screen the app keeps a phone-like width, centred, instead
      // of stretching cards and the calendar across the whole window.
      //
      // Android draws apps behind its navigation bar (|||, O, <), so every
      // screen, sheet and dialog is lifted above it here. Without this, Save
      // buttons at the bottom sat under the bar and taps missed them. While
      // the keyboard is open it already covers the bar, so nothing is added.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final bar = media.padding.bottom;
        final keyboard = media.viewInsets.bottom - bar;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: EdgeInsets.only(bottom: bar),
            child: MediaQuery(
              data: media.removePadding(removeBottom: true).copyWith(
                    viewInsets: media.viewInsets.copyWith(
                      bottom: keyboard > 0 ? keyboard : 0,
                    ),
                  ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      home: const _Gate(),
    );
  }
}

/// Asks for a language on a new device, then shows the account screen until
/// someone is signed in, then the onboarding quiz until it has been completed
/// once, then the app for whichever role was chosen: a partner gets her
/// shared view as his home screen, with none of the tracking tabs.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsProvider);

    if (language.isLoading || session.isLoading || settings.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (language.valueOrNull == null) return const LanguageScreen();
    // Everyone signs in first; the quiz and the app come after.
    if (session.valueOrNull == null) return const AccountScreen();
    // Then agreement to the current terms and consent for health data, once.
    final consent = ref.watch(legalConsentProvider);
    if (consent.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (consent.valueOrNull != true) return const LegalConsentScreen();

    final current = settings.valueOrNull;
    // Unreadable settings must not lock her out of her own data.
    if (current == null) return const AppShell();
    // An editor account always gets the editor panel. Before the quiz the
    // app waits for the answer so an editor never sees the quiz; after it,
    // it doesn't wait, so everyone else's app opens straight away.
    final editor = ref.watch(isEditorProvider);
    if (editor.valueOrNull == true) return const EditorHomeScreen();
    if (!current.onboardingComplete) {
      if (editor.isLoading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return const OnboardingScreen();
    }
    return current.profile.role == AppRole.partner
        ? const PartnerViewScreen()
        : const AppShell();
  }
}
