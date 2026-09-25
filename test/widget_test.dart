// Widget tests for University Point Locator.
//
// These cover the pure presentation widgets, which need no Supabase/network
// setup. The previous content was the untouched Flutter counter template, which
// pumped MyApp() and failed because RoleRouter reads Supabase.instance before
// it has been initialized.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:university_point_locator/widgets/info_row.dart';
import 'package:university_point_locator/widgets/stat_card.dart';

void main() {
  group('StatCard', () {
    testWidgets('renders its value, title and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'Active Buses',
              value: '12',
              icon: Icons.directions_bus,
              color: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('Active Buses'), findsOneWidget);
      expect(find.byIcon(Icons.directions_bus), findsOneWidget);
    });

    testWidgets('applies the supplied colour to the icon', (tester) async {
      const accent = Colors.deepPurple;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatCard(
              title: 'Routes',
              value: '3',
              icon: Icons.route,
              color: accent,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.route));
      expect(icon.color, accent);
    });
  });

  group('InfoRow', () {
    testWidgets('renders the supplied text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InfoRow(icon: Icons.location_on, text: 'Larkana Cantt'),
          ),
        ),
      );

      expect(find.text('Larkana Cantt'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('falls back to a blue icon when no colour is given',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InfoRow(icon: Icons.schedule, text: '08:30 AM'),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.schedule));
      expect(icon.color, Colors.blue);
    });
  });
}
