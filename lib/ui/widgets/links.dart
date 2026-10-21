import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web page or the phone's dialler, with a message if it can't.
Future<void> openExternal(
  BuildContext context,
  Uri uri,
  String failedMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(
      uri,
      mode: uri.scheme == 'tel'
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failedMessage)));
}
