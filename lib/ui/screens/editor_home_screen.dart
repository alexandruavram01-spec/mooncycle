import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../../state/providers.dart';
import '../widgets/account_sheet.dart';
import '../widgets/moon_face.dart';
import 'language_screen.dart';
import 'tip_library_screen.dart';

/// How many daily tips are pulled and how many have been rated.
final _countsProvider = FutureProvider.autoDispose<(int, int)>((ref) async {
  final ratings = await ref.watch(tipLibraryServiceProvider).ratings();
  return (
    ratings.where((r) => r.pulled).length,
    ratings.where((r) => r.likes + r.notFunny + r.notOkay > 0).length,
  );
});

/// The home screen for an editor account, shown instead of the quiz: how the
/// daily partner tips are landing, and the way into the tip library.
class EditorHomeScreen extends ConsumerWidget {
  const EditorHomeScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String filter) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TipLibraryScreen(initialFilter: filter),
      ),
    );
    // Back from the library: a tip may have been put back.
    if (context.mounted) ref.invalidate(_countsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final email = ref.watch(sessionProvider).valueOrNull ?? '';
    final counts = ref.watch(_countsProvider);
    final total = ref.watch(partnerMessagesProvider).allTips.length;

    Widget tile(String filter, int? n, String label, String hint,
        IconData icon) {
      return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(context, ref, filter),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                Text(
                  n == null ? '–' : '$n',
                  style: theme.textTheme.headlineMedium,
                ),
                Text(label, style: theme.textTheme.titleSmall),
                Text(hint, style: muted),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MoonCycle editor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_countsProvider),
          ),
          IconButton(
            tooltip: 'Language',
            icon: const Icon(Icons.language),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LanguageScreen(pushed: true),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => showAccountSheet(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
                children: [
                  const MoonFace(phase: CyclePhase.ovulatory, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Partner tips',
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text('Signed in as $email', style: muted),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (counts.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('${counts.error}', style: muted),
                ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  tile('pulled', counts.valueOrNull?.$1, 'Pulled',
                      'Flagged as not okay', Icons.flag_outlined),
                  tile('rated', counts.valueOrNull?.$2, 'Rated',
                      'Tips with feedback', Icons.thumbs_up_down_outlined),
                  tile('all', total, 'Daily tips', 'In this language',
                      Icons.format_list_bulleted),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'The wording is reviewed in the files in content/ and built '
                'into the app. To see the app the way she or he does, sign '
                'in with a test account in a private browser window.',
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
