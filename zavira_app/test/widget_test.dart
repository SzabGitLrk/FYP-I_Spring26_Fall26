import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zavira_app/main.dart';

void main() {
  testWidgets('Zavira app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(ZaviraApp());

    // Basic check: app loads without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}