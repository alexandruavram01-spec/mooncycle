import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/partner_tips.dart';
import '../../domain/profile.dart';
import '../../l10n/partner_messages.dart';
import '../../services/api_client.dart';
import '../../services/partner_link_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/account_sheet.dart';
import '../widgets/partner_invite.dart';
import '../widgets/partner_preview.dart';
import '../widgets/partner_stickers.dart';
import '../widgets/text_size.dart';
import 'language_screen.dart';
import 'partner_chat_screen.dart';
import 'partner_settings_screen.dart';
import 'tip_library_screen.dart';
import '../../l10n/ui.dart';

final _joinedProvider = FutureProvider<bool>(
  (ref) => ref.watch(partnerLinkServiceProvider).hasJoined(),
);

/// Refetched every time the screen is opened, so he never looks at a copy
/// cached from an earlier visit.
final _sharedSnapshotProvider = FutureProvider.autoDispose<SharedSnapshot?>(
  (ref) => ref.watch(partnerLinkServiceProvider).fetchShared(),
);

/// Fetches her summary again whenever his app comes back to the front. His
/// phone never stores what she shares, so once she disconnects him it is
/// gone from his screen the next time he looks, without him refreshing.
class _RefreshOnResume extends ConsumerStatefulWidget {
  const _RefreshOnResume({required this.child});

  final Widget child;

  @override
  ConsumerState<_RefreshOnResume> createState() => _RefreshOnResumeState();
}

class _RefreshOnResumeState extends ConsumerState<_RefreshOnResume> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () {
        ref.invalidate(_sharedSnapshotProvider);
        ref.invalidate(partnerChatProvider);
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The partner's side: enter her code once, then see what she shares.
///
/// This is the whole app for someone who chose the partner role, and a pushed
/// screen for someone who tracks their own cycle and is also a partner.
class PartnerViewScreen extends ConsumerWidget {
  const PartnerViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(_joinedProvider);
    final profile = ref.watch(profileProvider);
    final name = profile.partnerNickname;
    // Loads the editor check so the menu can offer the tip library.
    ref.watch(isEditorProvider);

    // Always Night, including when someone who tracks her own cycle opens
    // this screen from her Partner tab.
    return Theme(
      data: nightTheme,
      child: _RefreshOnResume(
        child: _buildScaffold(context, ref, joined, profile, name),
      ),
    );
  }

  /// He switches to tracking his own cycle, only after confirming: it
  /// disconnects him from her, their chat is deleted, and connecting again
  /// takes a new code from her (a paid connection for her).
  static Future<void> _switchToTracking(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Track your own cycle instead?')),
        content: Text(
          tr('You will be disconnected from her and your chat will be '
              'deleted. To connect again, she would need to create a new '
              'code, which is a one-time payment for her.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Switch')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(partnerLinkServiceProvider).leave();
    } on ApiException {
      // Not connected, or offline: her side can still disconnect him.
    }
    final current = ref.read(settingsProvider).value ?? const AppSettings();
    await ref.read(settingsProvider.notifier).replaceAll(
          current.copyWith(
            onboardingComplete: false,
            profile: const UserProfile(),
          ),
        );
  }

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> joined,
    UserProfile profile,
    String name,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          name.isEmpty
              ? tr('Her cycle')
              : trf("{name}'s cycle", {'name': name}),
        ),
        actions: [
          if (joined.value == true)
            IconButton(
              tooltip: tr('Refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(_sharedSnapshotProvider);
                ref.invalidate(partnerChatProvider);
              },
            ),
          if (profile.role == AppRole.partner)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PartnerSettingsScreen(),
                    ),
                  );
                } else if (value == 'language') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LanguageScreen(pushed: true),
                    ),
                  );
                } else if (value == 'text') {
                  showTextSizeSheet(context);
                } else if (value == 'account') {
                  showAccountSheet(context);
                } else if (value == 'library') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TipLibraryScreen(),
                    ),
                  );
                } else {
                  _switchToTracking(context, ref);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(tr('Her name and tip tone')),
                ),
                PopupMenuItem(
                  value: 'switch',
                  child: Text(tr('I track my own cycle')),
                ),
                PopupMenuItem(value: 'language', child: Text(tr('Language'))),
                PopupMenuItem(value: 'text', child: Text(tr('Text size'))),
                PopupMenuItem(value: 'account', child: Text(tr('Account'))),
                if (ref.read(isEditorProvider).value == true)
                  PopupMenuItem(
                    value: 'library',
                    child: Text(tr('Tip library')),
                  ),
              ],
            ),
        ],
      ),
      body: joined.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (isJoined) => isJoined ? const _SharedView() : const _CodeEntry(),
      ),
    );
  }
}

/// "How do you like your tips?", on his home screen until he confirms a
/// tone. His tips already use "a little humour" until then; the card shows
/// that as the current setting and an example in each tone.
class _ToneCard extends ConsumerWidget {
  const _ToneCard();

  static const confirmedKey = 'toneChosen';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile.quizAnswers[confirmedKey] == true) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = ref.watch(partnerMessagesProvider);
    final pulled = ref.watch(pulledTipsProvider).value ?? const <String>{};
    final example = PartnerTips.pickMove(
      messages,
      null,
      profile.partnerTone,
      DayKey.today(),
      pulled,
    );
    final settings = ref.read(settingsProvider.notifier);

    Future<void> save({PartnerTone? tone, bool confirm = false}) =>
        settings.updateProfile(
          profile.copyWith(
            partnerTone: tone,
            quizAnswers: confirm
                ? {...profile.quizAnswers, confirmedKey: true}
                : null,
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('How do you like your tips?'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              tr('Helpful suggestions, with as much humour as you like.'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            RadioGroup<PartnerTone>(
              groupValue: profile.partnerTone,
              onChanged: (value) => save(tone: value),
              child: Column(
                children: [
                  for (final tone in PartnerTone.values)
                    RadioListTile<PartnerTone>(
                      contentPadding: EdgeInsets.zero,
                      value: tone,
                      title: Text(tr(tone.label)),
                      subtitle: Text(tr(tone.hint)),
                    ),
                ],
              ),
            ),
            if (example != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4, bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Example tip'),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(example.text, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => save(confirm: true),
                child: Text(tr('Done')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before she connects: a general tip for today in his tone, so his first
/// screen is useful rather than empty. Nothing about her.
class _WelcomeTip extends ConsumerWidget {
  const _WelcomeTip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = ref.watch(profileProvider);
    final messages = ref.watch(partnerMessagesProvider);
    final pulled = ref.watch(pulledTipsProvider).value ?? const <String>{};
    final tip = PartnerTips.pickMove(
      messages,
      null,
      profile.partnerTone,
      DayKey.today(),
      pulled,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Welcome to MoonCycle'), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          tr('A little more understanding can go a long way.'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (tip != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 14, bottom: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(tr("Today's tip"),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(tip.text, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
      ],
    );
  }
}

class _CodeEntry extends ConsumerStatefulWidget {
  const _CodeEntry();

  @override
  ConsumerState<_CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends ConsumerState<_CodeEntry> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(partnerLinkServiceProvider).join(_controller.text);
      if (!mounted) return;
      ref.invalidate(_joinedProvider);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _WelcomeTip(),
        const SizedBox(height: 18),
        const _ToneCard(),
        Text(tr('Connect with your partner'),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(tr('Enter her pairing code'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          tr('She creates it under Partner in her app. You will see only the '
          'summary she chooses to share.'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          enabled: !_busy,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          maxLength: 8,
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: tr('ABCD2345'),
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? tr('Connecting…') : tr('Connect')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: sharePartnerInvite,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(tr('Send invitation')),
        ),
      ],
    );
  }
}

class _SharedView extends ConsumerWidget {
  const _SharedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final shared = ref.watch(_sharedSnapshotProvider);
    final profile = ref.watch(profileProvider);
    final messages = ref.watch(partnerMessagesProvider);
    final name = profile.partnerNickname;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const _ToneCard(),
        // The name used to be asked in the quiz; it now lives in the menu
        // (Name and tone), so it is offered here until he sets one.
        if (name.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('What do you call her?')),
              subtitle: Text(tr('Add her name or a nickname.')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PartnerSettingsScreen(),
                ),
              ),
            ),
          ),
        shared.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('$e'),
            ),
          ),
          data: (value) => value == null
              ? Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(tr('Nothing is being shared with you right now.')),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (messages.asks[value.ask] case final ask?) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: Sticker(
                          key: ValueKey('ask-${value.ask}'),
                          header: trf('{name} asks', {
                                'name': name.isEmpty ? tr('She') : name,
                              }) +
                              (value.askAt == null
                                  ? ''
                                  : ' · ${_ago(value.askAt!)}'),
                          text: ask.text,
                          icon: askIcons[value.ask] ?? Icons.favorite,
                          stamp: value.reaction == PartnerReactions.done
                              ? tr('Delivered')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(tr('Your reply'), style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      // Nothing is sent until he taps one.
                      ReplyChips(
                        options: {
                          PartnerReactions.special: ask.reply,
                          ...messages.replies,
                        },
                        selected: value.reaction,
                        onSelected: (key) => _act(
                          context,
                          ref,
                          (service) => service.react(key),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    PartnerPreview(
                      snapshot: value.snapshot,
                      name: name,
                      tone: profile.partnerTone,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trf('Updated {when}', {'when': _ago(value.updatedAt)}),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _OfferPicker(
                      name: name,
                      messages: messages,
                      phase: value.snapshot.phase,
                      offer: value.offer,
                      reply: value.offerReply,
                      onOffer: (key) => _act(
                        context,
                        ref,
                        (service) => service.sendOffer(key),
                      ),
                    ),
                  ],
                ),
        ),
        const PartnerChatButton(),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(tr('Use a different code?')),
                  content: Text(
                    tr('You will be disconnected from her and your chat will '
                        'be deleted. To connect again, she would need to '
                        'create a new code, which is a one-time payment for '
                        'her.'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr('Cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(tr('Disconnect')),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                await ref.read(partnerLinkServiceProvider).leave();
                if (context.mounted) ref.invalidate(_joinedProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            child: Text(tr('Use a different code')),
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return tr('just now');
    if (diff.inHours < 1) return trf('{n} min ago', {'n': diff.inMinutes});
    if (diff.inDays < 1) return trf('{n} h ago', {'n': diff.inHours});
    return trCount(diff.inDays, '{n} day ago', '{n} days ago');
  }

  /// Runs one of his one-tap actions, then refreshes the screen.
  static Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(PartnerLinkService service) action,
  ) async {
    try {
      await action(ref.read(partnerLinkServiceProvider));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (context.mounted) ref.invalidate(_sharedSnapshotProvider);
  }
}

/// What he can offer her without being asked, with the offers that suit her
/// current phase first, and her answer as a sticker once she has given one.
class _OfferPicker extends StatelessWidget {
  const _OfferPicker({
    required this.name,
    required this.messages,
    required this.phase,
    required this.offer,
    required this.reply,
    required this.onOffer,
  });

  final String name;
  final PartnerMessages messages;
  final CyclePhase? phase;
  final String? offer;
  final String? reply;
  final ValueChanged<String?> onOffer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = name.isEmpty ? tr('She') : name;
    final replyLabel = messages.offerReplies[reply];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Offer something'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              trf('{name} gets it as a sticker and can answer with one tap.',
                  {'name': who}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (replyLabel != null) ...[
              const SizedBox(height: 22),
              Center(
                child: Sticker(
                  key: ValueKey('reply-$offer-$reply'),
                  header: trf('{name} answered', {'name': who}),
                  text: replyLabel,
                  icon: Icons.favorite,
                  tilt: 0.04,
                ),
              ),
              const SizedBox(height: 18),
            ] else
              const SizedBox(height: 12),
            ReplyChips(
              options: {
                for (final key in PartnerOffers.forPhase(messages, phase))
                  key: messages.offers[key]!,
              },
              selected: offer,
              onSelected: onOffer,
              icons: offerIcons,
              collapsedCount: 8,
            ),
          ],
        ),
      ),
    );
  }
}
