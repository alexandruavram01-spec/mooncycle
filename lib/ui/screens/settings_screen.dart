import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/quiz.dart';
import '../../legal.dart';
import '../../state/providers.dart';
import '../widgets/account_sheet.dart';
import '../widgets/links.dart';
import 'ai_notes_screen.dart';
import 'get_help_screen.dart';
import 'language_screen.dart';
import 'onboarding_screen.dart';
import 'tip_library_screen.dart';
import '../../l10n/ui.dart';
import '../widgets/text_size.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).value;
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
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(tr('Account'), style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(ref.watch(sessionProvider).value ?? ''),
            subtitle: Text(tr('Sign out or delete your account.')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccountSheet(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(
              ref.watch(languageProvider).value?.label ?? tr('Language'),
            ),
            subtitle: Text(tr('Language of the app and of partner tips.')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LanguageScreen(pushed: true),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(tr('Text size')),
            subtitle: Text(tr(
              (ref.watch(textSizeProvider).value ?? TextSize.normal).label,
            )),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showTextSizeSheet(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.health_and_safety_outlined),
            title: Text(tr('Get help now')),
            subtitle: Text(tr('Emergency and urgent help services.')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GetHelpScreen()),
            ),
          ),
          if (ref.watch(isEditorProvider).value == true)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: Text(tr('Tip library')),
              subtitle: Text(tr('Ratings and pulled partner tips.')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TipLibraryScreen(),
                ),
              ),
            ),
          const Divider(height: 40),
          Text(tr('Your goal'), style: theme.textTheme.titleMedium),
          if (questionsLeft > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.more_time),
              title: Text(tr('Finish your quiz')),
              subtitle: Text(
                trCount(
                  questionsLeft,
                  '{n} question left. Your answers so far are kept.',
                  '{n} questions left. Your answers so far are kept.',
                ),
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
            title: Text(tr(journey?.name ?? profile.goal.label)),
            subtitle: Text(tr('Choose your journey again to change it.')),
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
            title: Text(tr('Show estimated fertile days')),
            subtitle: Text(tr('For information. It is not contraception.')),
            onChanged: (v) =>
                notifier.updateProfile(profile.copyWith(showFertileDays: v)),
          ),
          if (ref.watch(herInsightsEnabledProvider))
            ..._insightCards(context, ref),
          const Divider(height: 40),
          Text(tr('Reminders'), style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.periodReminder,
            title: Text(tr('Period is coming')),
            subtitle: Text(
              trCount(reminders.periodReminderDaysBefore, '{n} day before',
                  '{n} days before'),
            ),
            onChanged: (v) =>
                notifier.updateReminders(reminders.copyWith(periodReminder: v)),
          ),
          if (reminders.periodReminder)
            Slider(
              value: reminders.periodReminderDaysBefore.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: trCount(
                  reminders.periodReminderDaysBefore, '{n} day', '{n} days'),
              onChanged: (v) => notifier.updateReminders(
                reminders.copyWith(periodReminderDaysBefore: v.round()),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.fertileWindowReminder,
            title: Text(tr('Fertile window starts')),
            onChanged: (v) => notifier
                .updateReminders(reminders.copyWith(fertileWindowReminder: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders.dailyLogReminder,
            title: Text(tr('Daily logging nudge')),
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
              title: Text(tr('Reminder time')),
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
                        ? tr('Notifications enabled')
                        : tr('Notification permission denied'),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.notifications_outlined),
            label: Text(tr('Grant notification permission')),
          ),
          const Divider(height: 40),
          Text(tr('Your data'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            tr('Your logs and quiz answers are stored only on this phone, not on '
                'our servers. Your phone\'s own backup (iCloud or your Google '
                'account) can keep a copy; without it, they cannot be recovered '
                'if you uninstall MoonCycle or lose your phone. Your account '
                'holds only your email and your partner connection. If you turn '
                'on partner sharing, only the summary you choose is sent to the '
                'server.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Delete my account and data')),
            subtitle: Text(
              tr('Removes your account from our server and everything MoonCycle '
                  'stored on this device.'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccountSheet(context),
          ),
          const Divider(height: 40),
          Text(tr('About MoonCycle'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            Legal.healthNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final (title, url) in [
            (tr('Privacy policy'), Legal.privacyUrl),
            (tr('Terms of use'), Legal.termsUrl),
            (tr('Health information notice'), Legal.healthUrl),
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
            trf(
              '{app} is provided by {company}, company number {number}, '
              '{address}.',
              {
                'app': Legal.appName,
                'company': Legal.company,
                'number': Legal.companyNumber,
                'address': Legal.address,
              },
            ),
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
    final memory = ref.watch(insightMemoryProvider).value;
    if (memory == null) return const [];
    final notifier = ref.read(insightMemoryProvider.notifier);
    final hidden = memory.notRelevant.length;

    return [
      const Divider(height: 40),
      Text(tr('Insight cards'), style: theme.textTheme.titleMedium),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: memory.screeningReminders,
        title: Text(tr('Cervical screening reminders')),
        subtitle: Text(
          tr('An occasional card about NHS cervical screening, for people aged '
              '25 to 64 with a cervix.'),
        ),
        onChanged: notifier.setScreeningReminders,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.auto_awesome_outlined),
        title: Text(tr('AI chat')),
        subtitle: Text(
          (ref.watch(aiNotesProvider).value ?? false)
              ? tr('On. Tap the chat bubble on Today.')
              : tr('Off. Ask questions about your cycle and your log.'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiNotesScreen()),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: memory.sexualWellbeing,
        title: Text(tr('Cards about sex and desire')),
        subtitle: Text(
          tr('For example when you log low desire and low mood on the same '
              'day. Only you see them.'),
        ),
        onChanged: notifier.setSexualWellbeing,
      ),
      if (hidden > 0)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.visibility_outlined),
          title: Text(
            trCount(hidden, 'Show {n} hidden card again',
                'Show {n} hidden cards again'),
          ),
          subtitle: Text(tr('Cards you marked "Not relevant to me".')),
          onTap: notifier.restoreHidden,
        ),
    ];
  }
}
