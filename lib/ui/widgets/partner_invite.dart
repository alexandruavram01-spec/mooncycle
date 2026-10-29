import 'package:share_plus/share_plus.dart';

import '../../l10n/ui.dart';

/// The message her partner sends her to ask for a code. It goes from his
/// own phone, through whatever app he picks: MoonCycle sends nothing itself.
const partnerInviteMessage =
    "Hi! ❤️ I've started using MoonCycle too. If you'd like, we can connect "
    'our accounts so I can understand better how to support you. You can '
    'send me a code from the Partner tab. You choose what I can see. 😊 '
    'https://mooncycle.fit';

/// Opens the phone's share menu with the message, in his language.
Future<void> sharePartnerInvite() =>
    SharePlus.instance.share(ShareParams(text: tr(partnerInviteMessage)));
