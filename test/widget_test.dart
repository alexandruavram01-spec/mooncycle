import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/data/log_repository.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/models.dart';
import 'package:mooncycle/main.dart';
import 'package:mooncycle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke tests. The real logic lives in `domain/` and is covered by the unit
/// tests; these only check that the widget tree builds and reacts to data,
/// with SQLite and SharedPreferences swapped for in-memory doubles.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpApp(WidgetTester tester, List<DayLog> logs) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          logRepositoryProvider.overrideWith(
            (ref) async => InMemoryLogRepository(logs),
          ),
        ],
        child: const MoonCycleApp(),
      ),
    );
    // Let the async providers resolve without waiting on the loading spinner's
    // animation, which never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('app builds and shows every navigation destination',
      (tester) async {
    await pumpApp(tester, const []);

    expect(find.byType(NavigationBar), findsOneWidget);
    // `findsWidgets`, not `findsOneWidget`: IndexedStack builds every tab, so
    // a label like "Calendar" appears both in the nav bar and in that
    // screen's app bar.
    for (final label in ['Today', 'Calendar', 'Patterns', 'Partner']) {
      expect(find.text(label), findsWidgets, reason: 'missing tab: $label');
    }
  });

  testWidgets('prompts for a first period when there is no history',
      (tester) async {
    await pumpApp(tester, const []);

    expect(find.text('Set my last period'), findsOneWidget);
  });

  testWidgets('shows the current cycle day once a period is logged',
      (tester) async {
    final start = DayKey.today().addDays(-4);
    final logs = List.generate(
      5,
      (i) => DayLog(date: start.addDays(i), flow: FlowIntensity.medium),
    );

    await pumpApp(tester, logs);

    expect(find.text('Day 5'), findsOneWidget);
    expect(find.text('Set my last period'), findsNothing);
  });
}
