import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/account_storage.dart';
import '../../domain/day_key.dart';
import '../../domain/partner_tips.dart';
import '../../domain/profile.dart';
import '../../l10n/partner_messages.dart';
import '../../services/api_client.dart';
import '../../services/partner_chat_service.dart';
import '../../state/providers.dart';
import '../widgets/partner_stickers.dart';
import '../../l10n/ui.dart';

final partnerChatServiceProvider =
    Provider((ref) => PartnerChatService(ref.watch(apiClientProvider)));

/// The chat between her and her partner, or null while they are not
/// connected. Refreshed by the chat screen while it is open.
final partnerChatProvider = FutureProvider<PartnerChat?>((ref) async {
  ref.watch(sessionProvider);
  // Her side refreshes with her pairing, only while she shares: reading the
  // pairing otherwise would ask the server for a code (and on his side
  // would create one for him).
  final tracker = ref.watch(profileProvider).role == AppRole.tracker;
  final sharing = ref.watch(settingsProvider).value?.sharing.enabled ?? false;
  if (tracker && !sharing) return null;
  if (tracker) ref.watch(pairingProvider);
  try {
    return await ref.watch(partnerChatServiceProvider).fetch();
  } on ApiException {
    return null;
  }
});

/// The newest message from the other one that this account has seen, on
/// this phone, for the "new" dot.
class PartnerChatSeen extends AsyncNotifier<int> {
  static const _base = 'mooncycle.partnerChat.seen';

  @override
  Future<int> build() async {
    final account = await ref.watch(accountStorageProvider.future);
    if (account == null) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AccountStorage.key(_base, account)) ?? 0;
  }

  Future<void> markSeen(int id) async {
    if (id <= (state.value ?? 0)) return;
    state = AsyncData(id);
    final account = await ref.read(accountStorageProvider.future);
    if (account == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AccountStorage.key(_base, account), id);
  }
}

final partnerChatSeenProvider =
    AsyncNotifierProvider<PartnerChatSeen, int>(PartnerChatSeen.new);

/// Opens the chat, with a dot when the other one sent something new. Shown
/// only while they are connected.
class PartnerChatButton extends ConsumerWidget {
  const PartnerChatButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(partnerChatProvider).value;
    if (chat == null) return const SizedBox.shrink();
    final seen = ref.watch(partnerChatSeenProvider).value ?? 0;
    final unread = chat.latestFromThem > seen;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PartnerChatScreen()),
        ),
        icon: Badge(
          isLabelVisible: unread,
          backgroundColor: scheme.error,
          smallSize: 10,
          child: const Icon(Icons.forum_outlined),
        ),
        label: Text(unread ? tr('Chat · new message') : tr('Chat')),
      ),
    );
  }
}

/// What a card says, in this phone's language.
String? partnerCardText(PartnerMessages messages, String code) {
  if (code.startsWith('special:')) {
    return messages.asks[code.substring(8)]?.reply;
  }
  return messages.asks[code]?.text ??
      messages.offerReplies[code] ??
      messages.offers[code] ??
      messages.replies[code];
}

/// The chat between her and her partner: their fixed cards and emojis, with
/// the date and time, and a like or a love from either of them. Kept on the
/// server for 90 days.
class PartnerChatScreen extends ConsumerStatefulWidget {
  const PartnerChatScreen({super.key});

  @override
  ConsumerState<PartnerChatScreen> createState() => _PartnerChatScreenState();
}

class _PartnerChatScreenState extends ConsumerState<PartnerChatScreen> {
  final _emoji = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  int _lastCount = 0;

  /// Letters and numbers, which the chat does not send.
  static final _notEmoji = RegExp(r'[\p{L}\p{N}]', unicode: true);

  @override
  void initState() {
    super.initState();
    // New messages show up while the chat is open.
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => ref.invalidate(partnerChatProvider),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.invalidate(partnerChatProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _emoji.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _sending = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        ref.invalidate(partnerChatProvider);
        if (ref.read(profileProvider).role == AppRole.tracker &&
            (ref.read(settingsProvider).value?.sharing.enabled ?? false)) {
          ref.invalidate(pairingProvider);
        }
      }
    }
  }

  Future<void> _sendEmoji() async {
    final text = _emoji.text.trim();
    if (text.isEmpty) return;
    if (_notEmoji.hasMatch(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Only emojis can be sent here.'))),
      );
      return;
    }
    _emoji.clear();
    await _run(() => ref.read(partnerChatServiceProvider).sendEmoji(text));
  }

  Future<void> _react(PartnerChatMessage message, bool isHer, String kind) {
    final mine = isHer ? message.herReaction : message.hisReaction;
    return _run(
      () => ref
          .read(partnerChatServiceProvider)
          .react(message.id, mine == kind ? null : kind),
    );
  }

  /// The fixed cards this one can send now: her asks, and her answers to a
  /// fresh offer; his offers, and his replies to a fresh ask.
  Future<void> _pickCard(PartnerChat chat) async {
    final messages = ref.read(partnerMessagesProvider);
    final service = ref.read(partnerLinkServiceProvider);
    final fresh = DateTime.now().subtract(const Duration(hours: 24));
    PartnerChatMessage? latest(bool Function(PartnerChatMessage) test) {
      for (final m in chat.messages.reversed) {
        if (test(m)) return m.sentAt.isAfter(fresh) ? m : null;
      }
      return null;
    }

    final sections = <(String, Map<String, String>, Future<void> Function(String))>[];
    if (chat.isHer) {
      final offer = latest(
        (m) => !m.fromHer && !m.emoji && messages.offers.containsKey(m.body),
      );
      if (offer != null) {
        sections.add((
          tr('Answer their offer'),
          messages.offerReplies,
          service.replyToOffer,
        ));
      }
      sections.add((
        tr('Ask'),
        {
          for (final MapEntry(:key, :value) in messages.asks.entries)
            key: value.text,
        },
        service.sendAsk,
      ));
    } else {
      final ask = latest(
        (m) => m.fromHer && !m.emoji && messages.asks.containsKey(m.body),
      );
      if (ask != null) {
        sections.add((
          tr('Reply to her'),
          {
            PartnerReactions.special: messages.asks[ask.body]!.reply,
            ...messages.replies,
          },
          service.react,
        ));
      }
      sections.add((tr('Offer'), messages.offers, service.sendOffer));
    }

    final picked = await showModalBottomSheet<(String, Future<void> Function(String))>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            for (final (title, options, send) in sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final MapEntry(:key, :value) in options.entries)
                    ActionChip(
                      avatar: Icon(
                        askIcons[key] ?? offerIcons[key] ?? Icons.favorite,
                        size: 18,
                      ),
                      label: Text(value),
                      onPressed: () => Navigator.of(context).pop((key, send)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    final (key, send) = picked;
    await _run(() => send(key));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chatAsync = ref.watch(partnerChatProvider);
    final chat = chatAsync.value;
    final messages = ref.watch(partnerMessagesProvider);

    // Seen up to the newest; scrolled down when something arrives.
    if (chat != null) {
      final latest = chat.latestFromThem;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(partnerChatSeenProvider.notifier).markSeen(latest);
      });
      if (chat.messages.length != _lastCount) {
        _lastCount = chat.messages.length;
        _toBottom();
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Chat'))),
      body: chat == null
          ? Center(
              child: chatAsync.isLoading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr('Connect with your partner to chat.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: chat.messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              tr('No messages yet. Send a card or an emoji.'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: chat.messages.length,
                          itemBuilder: (context, i) {
                            final m = chat.messages[i];
                            final previous = i > 0 ? chat.messages[i - 1] : null;
                            final day = DayKey.fromDateTime(m.sentAt);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (previous == null ||
                                    DayKey.fromDateTime(previous.sentAt) != day)
                                  _DayDivider(day: day),
                                _PartnerBubble(
                                  message: m,
                                  mine: chat.mine(m),
                                  isHer: chat.isHer,
                                  text: m.emoji
                                      ? m.body
                                      : partnerCardText(messages, m.body) ??
                                          '…',
                                  icon: m.emoji
                                      ? null
                                      : askIcons[m.body] ??
                                          offerIcons[m.body] ??
                                          Icons.favorite,
                                  onReact: _sending
                                      ? null
                                      : (kind) => _react(m, chat.isHer, kind),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: chat.isHer
                              ? tr('Send an ask')
                              : tr('Send an offer'),
                          onPressed: _sending ? null : () => _pickCard(chat),
                          icon: const Icon(Icons.style_outlined),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _emoji,
                            maxLength: 40,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendEmoji(),
                            decoration: InputDecoration(
                              hintText: tr('Emojis only 😊'),
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filled(
                          tooltip: tr('Send'),
                          onPressed: _sending ? null : _sendEmoji,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});

  final DayKey day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DayKey.today();
    final label = day == today
        ? tr('Today')
        : day == today.addDays(-1)
            ? tr('Yesterday')
            : DateFormat.yMMMd(UiText.romanian ? 'ro' : 'en_GB')
                .format(DateTime(day.year, day.month, day.day));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _PartnerBubble extends StatelessWidget {
  const _PartnerBubble({
    required this.message,
    required this.mine,
    required this.isHer,
    required this.text,
    required this.icon,
    required this.onReact,
  });

  final PartnerChatMessage message;
  final bool mine;
  final bool isHer;
  final String text;
  final IconData? icon;
  final void Function(String kind)? onReact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final myReaction = isHer ? message.herReaction : message.hisReaction;
    final theirReaction = isHer ? message.hisReaction : message.herReaction;
    final time = DateFormat.Hm().format(message.sentAt);
    final muted =
        theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    Widget reaction(String kind, IconData on, IconData off, Color color) {
      final chosen = myReaction == kind;
      return IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        tooltip: kind == 'like' ? tr('Like') : tr('Love'),
        onPressed: onReact == null ? null : () => onReact!(kind),
        icon: Icon(
          chosen ? on : off,
          color: chosen ? color : scheme.onSurfaceVariant,
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: message.emoji
                          ? Colors.transparent
                          : mine
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(mine ? 18 : 4),
                        bottomRight: Radius.circular(mine ? 4 : 18),
                      ),
                    ),
                    child: Padding(
                      padding: message.emoji
                          ? const EdgeInsets.symmetric(horizontal: 4)
                          : const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                      child: message.emoji
                          ? Text(text, style: const TextStyle(fontSize: 40))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 18,
                                  color: mine
                                      ? scheme.onPrimary
                                      : scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    text,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: mine
                                          ? scheme.onPrimary
                                          : scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  // The other one's like or love, on the corner.
                  if (theirReaction != null)
                    Positioned(
                      bottom: -10,
                      right: mine ? null : -6,
                      left: mine ? -6 : null,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Icon(
                          theirReaction == 'love'
                              ? Icons.favorite
                              : Icons.thumb_up,
                          size: 14,
                          color: theirReaction == 'love'
                              ? const Color(0xFFE5809A)
                              : scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!mine) const SizedBox(width: 4),
                  Text(time, style: muted),
                  reaction(
                    'like',
                    Icons.thumb_up,
                    Icons.thumb_up_outlined,
                    scheme.primary,
                  ),
                  reaction(
                    'love',
                    Icons.favorite,
                    Icons.favorite_border,
                    const Color(0xFFE5809A),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
