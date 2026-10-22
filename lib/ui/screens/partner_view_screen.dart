import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../domain/enums.dart';
import '../../domain/partner_tips.dart';
import '../../domain/profile.dart';
import '../../l10n/partner_messages.dart';
import '../../services/partner_link_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/account_sheet.dart';
import '../widgets/partner_preview.dart';
import '../widgets/partner_stickers.dart';
import 'language_screen.dart';
import 'partner_settings_screen.dart';
import 'tip_library_screen.dart';

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
      onResume: () => ref.invalidate(_sharedSnapshotProvider),
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

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> joined,
    UserProfile profile,
    String name,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Her cycle' : "$name's cycle"),
        actions: [
          if (joined.valueOrNull == true)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(_sharedSnapshotProvider),
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
                } else if (value == 'account') {
                  showAccountSheet(context);
                } else if (value == 'restart') {
                  confirmStartOver(context, ref);
                } else if (value == 'library') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TipLibraryScreen(),
                    ),
                  );
                } else {
                  // Back to the first question, as someone tracking a cycle.
                  final current = ref.read(settingsProvider).valueOrNull ??
                      const AppSettings();
                  ref.read(settingsProvider.notifier).replaceAll(
                        current.copyWith(
                          onboardingComplete: false,
                          profile: const UserProfile(),
                        ),
                      );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Name and tone'),
                ),
                const PopupMenuItem(
                  value: 'switch',
                  child: Text('I track my own cycle'),
                ),
                const PopupMenuItem(value: 'language', child: Text('Language')),
                const PopupMenuItem(value: 'account', child: Text('Account')),
                if (ref.read(isTestAccountProvider))
                  const PopupMenuItem(
                    value: 'restart',
                    child: Text('Start over'),
                  ),
                if (ref.read(isEditorProvider).valueOrNull == true)
                  const PopupMenuItem(
                    value: 'library',
                    child: Text('Tip library'),
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
        Text('Enter her pairing code', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'She creates it under Partner in her app. You will see only the '
          'summary she chooses to share.',
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
            hintText: 'ABCD2345',
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? 'Connecting…' : 'Connect'),
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
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Nothing is being shared with you right now.'),
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
                          header: '${name.isEmpty ? 'She' : name} asks'
                              '${value.askAt == null ? '' : ' · ${_ago(value.askAt!)}'}',
                          text: ask.text,
                          icon: askIcons[value.ask] ?? Icons.favorite,
                          stamp: value.reaction == PartnerReactions.done
                              ? 'Delivered'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Your reply', style: theme.textTheme.labelLarge),
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
                      'Updated ${_ago(value.updatedAt)}',
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
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
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
            child: const Text('Use a different code'),
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
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
    final who = name.isEmpty ? 'She' : name;
    final replyLabel = messages.offerReplies[reply];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Offer something', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '$who gets it as a sticker and can answer with one tap.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (replyLabel != null) ...[
              const SizedBox(height: 22),
              Center(
                child: Sticker(
                  key: ValueKey('reply-$offer-$reply'),
                  header: '$who answered',
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
