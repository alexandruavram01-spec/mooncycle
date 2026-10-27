import 'package:flutter/material.dart';

import '../../legal.dart';
import 'links.dart';
import '../../l10n/ui.dart';

/// The two boxes everyone ticks before using MoonCycle: the terms (with age
/// and the privacy policy), and explicit consent for health data, which UK
/// GDPR requires separately. Never ticked in advance.
class ConsentBoxes extends StatelessWidget {
  const ConsentBoxes({
    super.key,
    required this.terms,
    required this.health,
    required this.onTerms,
    required this.onHealth,
    this.enabled = true,
  });

  final bool terms;
  final bool health;
  final ValueChanged<bool> onTerms;
  final ValueChanged<bool> onHealth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget link(String label, String url) => TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          onPressed: () =>
              openExternal(context, Uri.parse(url), 'Could not open the page.'),
          child: Text(label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: terms,
          onChanged: enabled ? (v) => onTerms(v ?? false) : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            trf(
              "I'm {age} or over, I agree to the Terms of use, and I've read "
              'the Privacy policy.',
              {'age': Legal.minimumAge},
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        CheckboxListTile(
          value: health,
          onChanged: enabled ? (v) => onHealth(v ?? false) : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            tr('I give my explicit consent for MoonCycle to process my health '
            'information, such as periods, symptoms and mood, to provide the '
            'app. I can withdraw it at any time by deleting my data.'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Wrap(
          children: [
            link(tr('Terms of use'), Legal.termsUrl),
            link(tr('Privacy policy'), Legal.privacyUrl),
            link(tr('Health information'), Legal.healthUrl),
          ],
        ),
        const SizedBox(height: 4),
        Text(Legal.healthNotice, style: muted),
      ],
    );
  }
}
