import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/data/settings_store.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/models.dart';
import 'package:mooncycle/services/data_export.dart';

void main() {
  final logs = [
    DayLog(
      date: DayKey.parse('2026-10-15'),
      flow: FlowIntensity.heavy,
      symptoms: const {'Headache', 'Cramps'},
      energy: 2,
      notes: 'Long day, "rough" one',
      isPeriodStartOverride: true,
    ),
    DayLog(
      date: DayKey.parse('2026-10-16'),
      flow: FlowIntensity.medium,
      notes: '=1+1',
    ),
  ];

  test('the spreadsheet has a header and one row per day', () {
    final lines = DataExport.csv(logs).split('\r\n');
    expect(lines, hasLength(3));
    expect(lines.first, startsWith('date,flow,symptoms'));
    expect(lines[1], startsWith('2026-10-15,heavy,Cramps; Headache,2,'));
    expect(lines[1], contains(',yes,'));
  });

  test('quotes in notes are escaped and formulas never run', () {
    final csv = DataExport.csv(logs);
    expect(csv, contains('"Long day, ""rough"" one"'));
    expect(csv, contains("'=1+1"));
  });

  test('the full copy holds every day and the quiz answers', () {
    final data =
        jsonDecode(DataExport.json(logs, const AppSettings())) as Map;
    expect((data['logs'] as List), hasLength(2));
    expect(data['profile'], isA<Map>());
    expect(data['app'], 'MoonCycle');
  });
}
