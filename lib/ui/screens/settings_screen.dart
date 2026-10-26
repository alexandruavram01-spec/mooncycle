import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/quiz.dart';
import '../../legal.dart';
import '../../state/providers.dart';
import '../widgets/account_sheet.dart';
import '../widgets/export_data.dart';
import '../widgets/links.dart';
import 'ai_notes_screen.dart';
import 'get_help_screen.dart';
import 'language_screen.dart';
import 'onboarding_screen.dart';
import 'tip_library_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final reminders = settings.reminders;
    final profile = settings.profile;
    final notifier = ref.read(settingsProvider.notifier);
    final journey = journeyById(profile.journey);
    final resumeAt = profile.quizResumeAt;
    final questionsLeft = journey != null && resumeAt != null
        ? journey.questions.length - resumeAt
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Account', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(ref.watch(sessionProvider).valueOrNull ?? ''),
            subtitle: const Text('Sign out or delete your account.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccountSheet(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(
              ref.watch(languageProvider).valueOrNull?.label ?? 'Language',
            ),
            subtitle: const Text('Language of partner tips and messages.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LanguageScreen(pushed: true),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Get help now'),
            subtitle: const Text('Emergency and urgent help services.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GetHelpScreen()),
            ),
          ),
          if (ref.watch(isEditorProvider).valueOrNull == true)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Tip library'),
              subtitle: const Text('Ratings and pulled partner tips.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TipLibraryScreen(),
                ),
              ),
            ),
          const Divider(height: 40),
          Text('Your goal', style: theme.textTheme.titleMedium),
          if (questionsLeft > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.more_time),
              title: const Text('Finish your quiz'),
              subtitle: Text(
                '$questionsLeft question${questionsLeft == 1 ? '' : 's'} '
                'left. Your answers so far are kept.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const OnboardingScreen(entry: OnboardingEntry.resume),
                ),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(journey?.name ?? profile.goal.label),
            subtitle: const Text('Choose your journey again to change it.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const OnboardingScreen(entry: OnboardingEntry.retake),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: profile.showFertileDays,
            title: const Text('Show estimated fertile days'),
            subtitle: const Text('For information. It is not contraception.'),
            onChanged: (v) => notifier
                .updateProfile(profile.copyWith(showFertileDays: v)),
          ),
          if (ref.watch(herInsightsEnabledProvider))
            ..._insightCards(context, ref),
          const Divider(height: 40),
          Text('Reminders', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.periodReminder,
            title: const Text('Period is coming'),
            subtitle: Text(
              '${reminders.periodReminderDaysBefore} days before',
            ),
            onChanged: (v) => notifier
                .updateReminders(reminders.copyWith(periodReminder: v)),
          ),
          if (reminders.periodReminder)
            Slider(
              value: reminders.periodReminderDaysBefore.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${reminders.periodReminderDaysBefore} days',
              onChanged: (v) => notifier.updateReminders(
                reminders.copyWith(periodReminderDaysBefore: v.round()),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.fertileWindowReminder,
            title: const Text('Fertile window starts'),
            onChanged: (v) => notifier
                .updateReminders(reminders.copyWith(fertileWindowReminder: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.dailyLogReminder,
            title: const Text('Daily logging nudge'),
            subtitle: Text(
              '${reminders.dailyLogHour.toString().padLeft(2, '0')}:'
              '${reminders.dailyLogMinute.toString().padLeft(2, '0')}',
            ),
            onChanged: (v) => notifier
                .updateReminders(reminders.copyWith(dailyLogReminder: v)),
          ),
          if (reminders.dailyLogReminder)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder time'),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: reminders.dailyLogHour,
                    minute: reminders.dailyLogMinute,
                  ),
                );
                if (picked == null) return;
                await notifier.updateReminders(
                  reminders.copyWith(
                    dailyLogHour: picked.hour,
                    dailyLogMinute: picked.minute,
                  ),
                );
              },
            ),
          TextButton.icon(
            onPressed: () async {
              final granted = await ref
                  .read(notificationServiceProvider)
                  .requestPermissions();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    granted
                        ? 'Notifications enabled'
                        : 'Notification permission denied',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Grant notification permission'),
          ),
          const Divider(height: 40),
          Text('Your data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Your logs and quiz answers are stored only on this phone, not on '
            'our servers. If you uninstall MoonCycle or lose your phone, they '
            'cannot be recovered, so save a copy from time to time with '
            'Export my data. Your account holds only your email and your '
            'partner connection. If you turn on partner sharing, only the '
            'summary you choose is sent to the server.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export my data'),
            subtitle: const Text(
              'Save a copy of your logs and quiz answers to Drive, email or '
              'your files: a spreadsheet and a full copy.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => exportMyData(context, ref),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete my account and data'),
            subtitle: const Text(
              'Removes your account from our server and everything MoonCycle '
              'stored on this device.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccountSheet(context),
          ),
          const Divider(height: 40),
          Text('About MoonCycle', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            Legal.healthNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final (title, url) in [
            ('Privacy policy', Legal.privacyUrl),
            ('Terms of use', Legal.termsUrl),
            ('Health information notice', Legal.healthUrl),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openExternal(
                context,
                Uri.parse(url),
                'Could not open the page.',
              ),
            ),
          Text(
            '${Legal.appName} is provided by ${Legal.company}, '
            'company number ${Legal.companyNumber}, ${Legal.address}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Her insight cards' settings. Nothing here is on until she turns it on.
  List<Widget> _insightCards(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memory = ref.watch(insightMemoryProvider).valueOrNull;
    if (memory == null) return const [];
    final notifier = ref.read(insightMemoryProvider.notifier);
    final hidden = memory.notRelevant.length;

    return [
      const Divider(height: 40),
      Text('Insight cards', style: theme.textTheme.titleMedium),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: memory.screeningReminders,
        title: const Text('Cervical screening reminders'),
        subtitle: const Text(
          'An occasional card about NHS cervical screening, for people aged '
          '25 to 64 with a cervix.',
        ),
        onChanged: notifier.setScreeningReminders,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text('AI-written notes'),
        subtitle: Text(
          (ref.watch(aiNotesProvider).valueOrNull ?? false)
              ? 'On. Your daily card is written around your own log.'
              : 'Off. Have your daily card written around your own log.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiNotesScreen()),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: memory.sexualWellbeing,
        title: const Text('Cards about sex and desire'),
        subtitle: const Text(
          'For example when you log low desire and low mood on the same '
          'day. Only you see them.',
        ),
        onChanged: notifier.setSexualWellbeing,
      ),
      if (hidden > 0)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.visibility_outlined),
          title: Text(
            'Show $hidden hidden card${hidden == 1 ? '' : 's'} again',
          ),
          subtitle: const Text('Cards you marked "Not relevant to me".'),
          onTap: notifier.restoreHidden,
        ),
    ];
  }
}
