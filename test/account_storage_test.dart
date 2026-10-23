import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/data/account_storage.dart';
import 'package:mooncycle/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('each email has its own stable storage name', () {
    final her = AccountStorage.idFor('review-her@ioncodex.org');
    expect(AccountStorage.idFor(' Review-Her@IonCodex.org '), her);
    expect(AccountStorage.idFor('review-partner@ioncodex.org'), isNot(her));
    expect(her, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('the data shared before goes to the first account only', () async {
    SharedPreferences.setMockInitialValues({
      'mooncycle.settings.v1': '{"onboardingComplete":true}',
    });
    final first = AccountStorage.idFor('first@example.com');
    final second = AccountStorage.idFor('second@example.com');

    await AccountStorage.claimLegacy(first);
    await AccountStorage.claimLegacy(second);

    expect((await SettingsStore(first).load()).onboardingComplete, isTrue);
    expect((await SettingsStore(second).load()).onboardingComplete, isFalse);
    expect(await AccountStorage.legacyOwner(), first);
  });

  test('a second account never sees the first one\'s settings', () async {
    SharedPreferences.setMockInitialValues({});
    final her = SettingsStore(AccountStorage.idFor('her@example.com'));
    final other = SettingsStore(AccountStorage.idFor('other@example.com'));

    await her.save(const AppSettings(onboardingComplete: true));

    expect((await her.load()).onboardingComplete, isTrue);
    expect((await other.load()).onboardingComplete, isFalse);
  });

  test('erasing an account removes only its own data', () async {
    SharedPreferences.setMockInitialValues({});
    final herId = AccountStorage.idFor('her@example.com');
    final otherId = AccountStorage.idFor('other@example.com');
    await SettingsStore(herId).save(const AppSettings(onboardingComplete: true));
    await SettingsStore(otherId)
        .save(const AppSettings(onboardingComplete: true));

    await AccountStorage.eraseKeys(herId);

    expect((await SettingsStore(herId).load()).onboardingComplete, isFalse);
    expect((await SettingsStore(otherId).load()).onboardingComplete, isTrue);
  });
}
