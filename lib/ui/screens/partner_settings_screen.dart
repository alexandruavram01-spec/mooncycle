import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../domain/profile.dart';
import '../../state/providers.dart';

/// His name for her and how funny his tips should be. No longer part of the
/// quiz; reached from the menu on his home screen.
class PartnerSettingsScreen extends ConsumerStatefulWidget {
  const PartnerSettingsScreen({super.key});

  @override
  ConsumerState<PartnerSettingsScreen> createState() =>
      _PartnerSettingsScreenState();
}

class _PartnerSettingsScreenState extends ConsumerState<PartnerSettingsScreen> {
  late final _name =
      TextEditingController(text: ref.read(profileProvider).partnerNickname);
  late PartnerTone _tone = ref.read(profileProvider).partnerTone;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final current =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    try {
      await ref.read(settingsProvider.notifier).replaceAll(
            current.copyWith(
              profile: current.profile.copyWith(
                partnerNickname: _name.text.trim(),
                partnerTone: _tone,
              ),
            ),
          );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Name and tone')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('What do you call her?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A name or a nickname. It stays on this device.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Ana',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'How funny should your tips be?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Jokes switch off on their own on days she might not feel like '
            'laughing, whatever you pick.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final tone in PartnerTone.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tone.label),
              subtitle: Text(tone.hint),
              trailing: _tone == tone
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : const Icon(Icons.circle_outlined),
              onTap: () => setState(() => _tone = tone),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
