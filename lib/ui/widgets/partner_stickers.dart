import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/day_key.dart';
import '../../domain/enums.dart';
import '../../domain/partner_tips.dart';
import '../../domain/profile.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'moon_face.dart';

/// Icons for the asks and offers, by code. Kept here because the domain
/// layer has no Flutter in it.
const Map<String, IconData> askIcons = {
  'A01': Icons.favorite,
  'A02': Icons.local_cafe,
  'A03': Icons.cookie,
  'A04': Icons.local_fire_department,
  'A05': Icons.nightlight_round,
  'A06': Icons.hearing,
  'A07': Icons.task_alt,
  'A08': Icons.restaurant,
  'A09': Icons.movie,
  'A10': Icons.icecream,
  'A11': Icons.directions_walk,
  'A12': Icons.celebration,
  'A13': Icons.sentiment_very_satisfied,
  'A14': Icons.volunteer_activism,
  'A16': Icons.shopping_bag,
  'A17': Icons.soap,
  'A18': Icons.mobile_off,
  'A19': Icons.favorite_border,
  'A20': Icons.free_breakfast,
  'A21': Icons.weekend,
  'A22': Icons.spa,
  'A23': Icons.chat_bubble_outline,
  'A24': Icons.mail_outline,
  'A25': Icons.shopping_cart,
  'A26': Icons.music_note,
  'A27': Icons.nights_stay,
  'A28': Icons.self_improvement,
};

const Map<String, IconData> offerIcons = {
  'O01': Icons.local_cafe,
  'O02': Icons.local_fire_department,
  'O03': Icons.restaurant,
  'O04': Icons.cleaning_services,
  'O05': Icons.spa,
  'O06': Icons.bathtub,
  'O07': Icons.self_improvement,
  'O08': Icons.movie,
  'O09': Icons.cake,
  'O10': Icons.icecream,
  'O11': Icons.wine_bar,
  'O12': Icons.luggage,
  'O17': Icons.free_breakfast,
  'O18': Icons.spa,
  'O19': Icons.shopping_cart,
  'O20': Icons.mobile_off,
  'O21': Icons.favorite,
  'O22': Icons.local_laundry_service,
  'O23': Icons.sentiment_very_satisfied,
  'O24': Icons.directions_walk,
  'O25': Icons.home,
  'O26': Icons.chat_bubble_outline,
};

/// A message between them, shown as a sticker: tilted, with a thick white
/// edge, popping in when it first appears. Give it a key that changes with
/// the message so a new one pops in again.
class Sticker extends StatelessWidget {
  const Sticker({
    super.key,
    required this.header,
    required this.text,
    required this.icon,
    this.stamp,
    this.tilt = -0.04,
  });

  final String header;
  final String text;
  final IconData icon;

  /// A rubber-stamp word across the corner, such as "Delivered".
  final String? stamp;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stampText = stamp;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.rotate(
        angle: tilt,
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 22, 16),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const MoonFace(phase: CyclePhase.ovulatory, size: 52),
                    Positioned(
                      right: -8,
                      bottom: -6,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 18, color: MoonColors.moonInk),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        header,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (stampText != null)
            Positioned(
              right: -8,
              top: -14,
              child: Transform.rotate(
                angle: 0.2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border:
                        Border.all(color: MoonColors.follicular, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stampText.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF2F7A5E),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One-tap answers. Tapping the chosen one again takes it back.
///
/// With [collapsedCount], only that many show at first, plus a "More" chip
/// for the rest. The chosen one always shows.
class ReplyChips extends StatefulWidget {
  const ReplyChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.icons = const {},
    this.enabled = true,
    this.collapsedCount,
  });

  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final Map<String, IconData> icons;
  final bool enabled;
  final int? collapsedCount;

  @override
  State<ReplyChips> createState() => _ReplyChipsState();
}

class _ReplyChipsState extends State<ReplyChips> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.options.entries.toList();
    final limit = widget.collapsedCount ?? entries.length;
    // Never a "More (1)": one extra chip takes the same room as the button.
    final collapsed = !_expanded && entries.length > limit + 1;
    final shown = collapsed
        ? [
            ...entries.take(limit),
            ...entries
                .skip(limit)
                .where((option) => option.key == widget.selected),
          ]
        : entries;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final option in shown)
          ChoiceChip(
            avatar: widget.icons[option.key] == null
                ? null
                : Icon(widget.icons[option.key], size: 18),
            label: Text(option.value),
            selected: widget.selected == option.key,
            onSelected: widget.enabled
                ? (on) => widget.onSelected(on ? option.key : null)
                : null,
          ),
        if (collapsed)
          ActionChip(
            avatar: const Icon(Icons.expand_more, size: 18),
            label: Text('More (${entries.length - limit})'),
            onPressed: () => setState(() => _expanded = true),
          ),
      ],
    );
  }
}

/// The first thing on her Today screen: the tip her partner got today, as a
/// message she can rate with one tap. "Not okay" takes it down for everyone
/// and he gets a different one. Hidden for the rest of the day once she has
/// rated it or closed it.
class PartnerTipBanner extends ConsumerStatefulWidget {
  const PartnerTipBanner({super.key});

  @override
  ConsumerState<PartnerTipBanner> createState() => _PartnerTipBannerState();
}

class _PartnerTipBannerState extends ConsumerState<PartnerTipBanner> {
  static const _dismissedKey = 'mooncycle.tipBanner.dismissed';

  /// `<day>:<tip id>` of the last tip she rated or closed.
  String? _dismissed;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _dismissed = prefs.getString(_dismissedKey);
        _loaded = true;
      });
    });
  }

  Future<void> _dismiss(String marker) async {
    setState(() => _dismissed = marker);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, marker);
  }

  Future<void> _rate(String code, String marker, String kind) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(tipLibraryServiceProvider).rate(code, kind);
      if (kind == 'not_okay') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('🚩 Taken down for everyone. They get a different '
                'tip.'),
          ),
        );
        // The replacement pops up here in its place.
        if (mounted) ref.invalidate(pulledTipsProvider);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              kind == 'like'
                  ? '👍 Glad that one works.'
                  : '😐 Noted. Fewer like that.',
            ),
          ),
        );
        if (mounted) await _dismiss(marker);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharing = ref.watch(settingsProvider).valueOrNull?.sharing;
    if (!_loaded || sharing == null || !sharing.enabled) {
      return const SizedBox.shrink();
    }
    final pairing = ref.watch(pairingProvider).valueOrNull;
    final snapshot = ref.watch(partnerSnapshotProvider);
    if (pairing == null || !pairing.linked || snapshot == null) {
      return const SizedBox.shrink();
    }

    // The same choice his app makes, so she sees the tip he gets today. It
    // is in her language; his may differ, but the code is the same.
    final pulled =
        ref.watch(pulledTipsProvider).valueOrNull ?? const <String>{};
    final tone = snapshot.jokes
        ? (pairing.partnerTone ?? PartnerTone.light)
        : PartnerTone.straight;
    final move = PartnerTips.pickMove(
      ref.watch(partnerMessagesProvider),
      snapshot.phase,
      tone,
      DayKey.today(),
      pulled,
    );
    if (move == null) return const SizedBox.shrink();
    final lineId = move.id;
    final marker = '${DayKey.today().iso}:$lineId';
    if (_dismissed == marker) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final ink = theme.colorScheme.onPrimaryContainer;

    Widget option(String emoji, String label, String kind) => ActionChip(
          avatar: Text(emoji),
          label: Text(label),
          onPressed: _busy ? null : () => _rate(lineId, marker, kind),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(marker),
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('💌', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Today's tip for your partner",
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: ink),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide for today',
                      icon: Icon(Icons.close, color: ink),
                      onPressed: () => _dismiss(marker),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '“${move.text}”',
                    style: theme.textTheme.titleMedium?.copyWith(color: ink),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'How does it feel to you?',
                  style: theme.textTheme.bodySmall?.copyWith(color: ink),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    option('👍', 'Nice', 'like'),
                    option('😐', 'Not funny', 'not_funny'),
                    option('🚩', 'Not okay', 'not_okay'),
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

/// Her one-tap asks to him, on her Today tab. Only one is active at a time,
/// and it stays on his screen for a day unless she takes it back. Shown
/// greyed out until a partner has connected, so she knows the feature is
/// there.
class PartnerNudgeCard extends ConsumerWidget {
  const PartnerNudgeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messages = ref.watch(partnerMessagesProvider);
    final pairing = ref.watch(pairingProvider).valueOrNull;
    if (pairing == null) return const SizedBox.shrink();
    final linked = pairing.linked;
    final ask = pairing.ask;
    final askLabel = messages.asks[ask]?.text;
    final replyLabel =
        PartnerReactions.label(messages, pairing.reaction, ask);

    Future<void> send(String? key) async {
      try {
        await ref.read(partnerLinkServiceProvider).sendAsk(key);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      if (context.mounted) ref.invalidate(pairingProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send a nudge', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                linked
                    ? 'One tap and it shows on their screen for a day. Tap '
                        'it again to take it back.'
                    : 'Once your partner connects (Partner tab), one tap '
                        'sends them any of these.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (linked && askLabel != null) ...[
                const SizedBox(height: 22),
                Center(
                  child: Sticker(
                    key: ValueKey('ask-$ask'),
                    header: 'You asked',
                    text: askLabel,
                    icon: askIcons[ask] ?? Icons.favorite,
                    stamp: pairing.reaction == PartnerReactions.done
                        ? 'Delivered'
                        : null,
                  ),
                ),
                if (replyLabel != null &&
                    pairing.reaction != PartnerReactions.done) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'They replied: $replyLabel',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
              ] else
                const SizedBox(height: 10),
              ReplyChips(
                options: {
                  for (final MapEntry(:key, :value) in messages.asks.entries)
                    key: value.text,
                },
                selected: ask,
                onSelected: send,
                icons: askIcons,
                enabled: linked,
                collapsedCount: 9,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// His offer, shown to her with one-tap answers. Nothing when there is none.
/// Used on her home screen and her Partner tab.
class PartnerOfferCard extends ConsumerWidget {
  const PartnerOfferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messages = ref.watch(partnerMessagesProvider);
    final pairing = ref.watch(pairingProvider).valueOrNull;
    final offer = pairing?.offer;
    final label = messages.offers[offer];
    if (pairing == null || !pairing.linked || offer == null || label == null) {
      return const SizedBox.shrink();
    }

    Future<void> reply(String? key) async {
      try {
        await ref.read(partnerLinkServiceProvider).replyToOffer(key);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      if (context.mounted) ref.invalidate(pairingProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: Column(
            children: [
              Sticker(
                key: ValueKey('offer-$offer'),
                header: 'They offer',
                text: label,
                icon: offerIcons[offer] ?? Icons.favorite,
                stamp: pairing.offerReply == OfferReplies.yes
                    ? 'Accepted'
                    : null,
                tilt: 0.03,
              ),
              const SizedBox(height: 16),
              Text('Your answer', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              ReplyChips(
                options: messages.offerReplies,
                selected: pairing.offerReply,
                onSelected: reply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
